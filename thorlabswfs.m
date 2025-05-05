classdef thorlabswfs < handle 
    % Matlab class to control Thorlabs Shack-Hartmann Wavefront Sensors of WFS series
    % It is a 'wrapper' to control the devices via .NET DLLs provided by Thorlabs.
    %
    % Instructions:
    % Download the WFS software from the Thorlabs website:
    % https://www.thorlabs.de/software_pages/ViewSoftwarePage.cfm?Code=WFS
    % Edit DLLPATHDEFAULT below to point to the location of the DLLs
    %
    % Example tested for WFS30-7AR wavefront sensor:
    % wfs = thorlabswfs;      % Create a wavefront sensor object. Shows a list of avialable devices
    % wfs.connect             % Connect the first (default) devce
    % wfs.connect(1025)       % Connect the sensor with the DevceID = 1025
    % wfs.connect('USB::0x1313::0x0000::1025') % Connect the sensor using ResourceName
    % wfs.configureDevice     % configures the sensor for max resolution (1936x1216 for WFS30-7AR)
    % wfs.configureDevice(2)  % configures the sensor for pre-defined resolution set number 2 = CAM_RES_WFS30_1024. See code for possible values
    % wfs.setReferencePlane   % set WFS reference plane to internal
    % wfs.adjustImageBrightness % call autoadjustment routine to set Camera Exposure and Gain
    % wfs.Pupil = [-0.5,-2.0,1.1,1.6] % set the Beam Pupil position [-0.5;-2.0] in mm and Beam Pupil Size [1.1;1.6] in mm
    % wfs.takeSpotfieldImage  % takes new image
    % wfs.Beam_Centroid       % get 1x4 vector with Beam Centroid position [X, Y] in mm and Beam diameter [X, Y] in mm
    % wfs.Pupil = wfs.Beam_Centroid % update pupil position and size with values of calculated beam centroid 
    % wfs.disconnect          % Disconnect sensor (not strictly necessary - device is disconnected automatically using destructor)
    % clear wfs               % Clear device object from memory
    %
    %
    % Author: Andriy Chmyrov 
    % Helmholtz Zentrum Muenchen, Deutschland
    % Email: andriy.chmyrov@helmholtz-muenchen.de
    % 
    %
    % Version History:
    % 1.0 16 Aug 2022 - initial implementation targeted on for WFS30-7AR
    
    properties (SetAccess = private)
       % These properties are within Matlab wrapper 
       Serial_Number;               % Device serial number
       Device_ID;                   % Device ID - required to open the WFS instrument in function init
       Resource_Name;               % specifies the interface of the device that is to be initialized
       Instrument_Name;             % Name of the connected instrument
       Instrument_Count;            % Number of available instruments
       Connected = false;           % Flag showing if device is connected
       MLA_Count;                   % Number of available MLA (multi-lens arrays)
       Exposure_Time_Min_s = nan;   % Minimal exposure time of the WFS camera in seconds
       Exposure_Time_Max_s = nan;   % Maximal exposure time of the WFS camera in seconds
       Exposure_Time_Incr_s = nan;  % Smallest possible increment of the exposure time in seconds
       Master_Gain_Min;             % Minimal linear master gain value of the WFS camera
       Master_Gain_Max;             % Maximal linear master gain value of the WFS camera
    end

    properties 
        Zernike_Order = 4;          % Zernike fit up to order
        Fourier_Order = 2;          % defines the highest Zernike order considered for calculating Fourier coefficients M, J0 and J45 as well as the Optometric parameters Sphere, Cylinder and Axis. Valid settings: 2, 4 or 6
        Cancel_Wavefront_Tilt = 0   % Flag to cancel average wavefront tip and tilt during calculations 
        Dynamic_Noise_Cut = 1;      % Flag to use dynamic noise cut features
    end

    properties (Dependent)
        Pupil;                      % 1x4 vector [ctrX, ctrY, diaX, diaY] with pre-defined Pupil center position [X, Y] in mm and Pupil diameter [X, Y] in mm
        Beam_Centroid;              % 1x4 vector [ctrX, ctrY, diaX, diaY] with calculated Beam Centroid position [X, Y] in mm and Beam diameter [X, Y] in mm
        Spotfield_Image;            % returns a copy of the spotfield image. Plot it using the command: figure, imagesc(rot90(wfs.Spotfield_Image,-1)), axis image, colormap gray
        Zernike;                    % Outputs a structure with a vector of the Zernike coefficients up to the desired number of Zernike modes, a vector summarizing these coefficients to rms amplitudes for each Zernike order and RoC (radius of curvature) in mm for a spherical wavefront.
        Wavefront;                  % Outputs a structure with Min, Max, Diff, Mean, RMS, Weighted_RMS parameters of the wavefront based on the spot deviations
        FourierOptometric;          % Outputs a structure with the Fourier and Optometric notations from the Zernike coefficients calculated in function WFS_ZernikeLsf.
        Black_Level_Offset;         % Set/get the black offset value of the WFS camera. A higher black level will increase the intensity level of a dark camera image.
        Exposure_Time;              % Set/get the exposure time of the WFS camera
        Master_Gain;                % Set/get the linear master gain of the WFS camera
    end

    properties (Hidden)
       % These are properties within the .NET environment. 
       deviceNET;                   % Device object within .NET
       Initialized = false;         % initialization flag
       Pupil_Defined = false;       % flag Pupil_Defined
       Zernike_Orders_Calculated;   % the calculated number of Zernike orders in function WFS_ZernikeLsf
    end

    properties (Constant, Hidden)
        % path to DLL files (edit as appropriate)
        DLLPATHDEFAULT = 'C:\Program Files (x86)\Microsoft.NET\Primary Interop Assemblies\';

        % DLL files to be loaded
        WFSDLL = 'Thorlabs.WFS.Interop64.dll';
        WFSCLASSNAME = 'Thorlabs.WFS.Interop64.WFS';

        % Pixel format defines
        PIXEL_FORMAT_MONO8 = 0;
        PIXEL_FORMAT_MONO16 = 1;

        % check full list of constants at C:\Program Files\IVI Foundation\VISA\Win64\Include\WFS.h

        % pre-defined image sizes for WFS30 instruments
        CAM_RES_WFS30_1936     =  0; % 1936x1216
        CAM_RES_WFS30_1216     =  1; % 1216x1216
        CAM_RES_WFS30_1024     =  2; % 1024x1024
        CAM_RES_WFS30_768      =  3; % 768x768
        CAM_RES_WFS30_512      =  4; % 512x512
        CAM_RES_WFS30_360      =  5; % 360x360 smallest!
        CAM_RES_WFS30_968_SUB2 =  6; % 968x608, subsampling 2x2
        CAM_RES_WFS30_608_SUB2 =  7; % 608x608, subsampling 2x2
        CAM_RES_WFS30_512_SUB2 =  8; % 512x512, subsampling 2x2
        CAM_RES_WFS30_384_SUB2 =  9; % 384x384, subsampling 2x2
        CAM_RES_WFS30_256_SUB2 = 10; % 256x256, subsampling 2x2
        CAM_RES_WFS30_180_SUB2 = 11; % 180x180, subsampling 2x2
        CAM_RES_WFS30_MAX_IDX  = 11;

        % Reference planes
        WFS_REF_INTERNAL = 0;
        WFS_REF_USER     = 1;

        % Pupil limits
        PUPIL_DIA_MIN_MM = 0.5; % for coarse check only
        PUPIL_DIA_MAX_MM = 12.0;
        PUPIL_CTR_MIN_MM = -8.0;
        PUPIL_CTR_MAX_MM = 8.0;

        maxZernikeModes = 66; % allocate Zernike array of 67 because index is 1..66
    end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% M E T H O D S - CONSTRUCTOR/DESCTRUCTOR
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    methods

        % =================================================================
        function h = thorlabswfs() % Constructor - Instantiate motor object
            h.loaddlls; % Load DLLs (if not already loaded)
            if ~h.Initialized
                h.deviceNET = Thorlabs.WFS.Interop64.WFS( System.IntPtr(0) );
                h.Initialized = true;

                str1 = System.Text.StringBuilder(Thorlabs.WFS.Interop64.WFS.BufferSize);
                str2 = System.Text.StringBuilder(Thorlabs.WFS.Interop64.WFS.BufferSize);
                retVal = h.deviceNET.revision_query(str1,str2);  
                fprintf('WFS instrument driver version: %s%s\n', str1.ToString, str2.ToString);

                [retVal, h.Instrument_Count] = h.deviceNET.GetInstrumentListLen(); %#ok<ASGLU> 
                if h.Instrument_Count > 1, ending = 's'; else, ending = ''; end
                fprintf('%d Thorlabs wavefront sensor%s found\n', h.Instrument_Count, ending);

                for kn = 0:h.Instrument_Count-1 % Note: The first instrument has index 0.
                    str1 = System.Text.StringBuilder(Thorlabs.WFS.Interop64.WFS.BufferSize);
                    str2 = System.Text.StringBuilder(Thorlabs.WFS.Interop64.WFS.BufferSize);
                    str3 = System.Text.StringBuilder(Thorlabs.WFS.Interop64.WFS.BufferSize);
                    [retVal, dev_id, dev_inuse] = h.deviceNET.GetInstrumentListInfo(int32(kn),str1,str2,str3); %#ok<ASGLU> 
                    fprintf('%d. Model: %s, Serial: %s, Address: %s, DeviceID: %d\n',kn+1, str1.ToString,str2.ToString,str3.ToString, dev_id);
                    h.Serial_Number = char(str2.ToString);
                    h.Resource_Name = char(str3.ToString);
                    h.Device_ID = dev_id;
                    if dev_inuse
                        fprintf(2,'Device seems to be in use - disconnect it and try again!\n');
                    end
                end
            end
        end

        % =================================================================
        function delete(h) % Destructor 
            if ~isempty(h.deviceNET) && h.Connected
                try
                    h.deviceNET.Dispose();
                    h.Connected = false;
                catch Exception  
                end
            end
            h.Initialized = false;
        end
    end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% M E T H O D S (Sealed) - INTERFACE IMPLEMENTATION
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

    methods (Sealed)

        % =================================================================
        function connect(h,resourceNameIn)  
        % Connect device
            if ~h.Connected
                if nargin < 2
                    resourceName = h.Resource_Name;
                elseif isnumeric(resourceNameIn) 
                    % DeviceID supplied as a number
                    resourceName = sprintf('USB::0x1313::0x0000::%d',resourceNameIn);
                elseif isstring(resourceNameIn) || ischar(resourceNameIn) 
                    % Full device address is supplied as a string or char array
                    resourceName = char(resourceNameIn);
                end
                h.deviceNET = Thorlabs.WFS.Interop64.WFS( System.String(resourceName), false, false );
                h.Resource_Name = resourceName;
                h.Device_ID = int32(sscanf(resourceName,'USB::0x1313::0x0000::%d'));

                str1 = System.Text.StringBuilder(Thorlabs.WFS.Interop64.WFS.BufferSize);
                str2 = System.Text.StringBuilder(Thorlabs.WFS.Interop64.WFS.BufferSize);
                str3 = System.Text.StringBuilder(Thorlabs.WFS.Interop64.WFS.BufferSize);
                str4 = System.Text.StringBuilder(Thorlabs.WFS.Interop64.WFS.BufferSize);
                retVal = h.deviceNET.GetInstrumentInfo(str1,str2,str3,str4);  
                h.Instrument_Name = char(str2.ToString);
                h.Serial_Number = char(str3.ToString);
                fprintf('Connected successfully to the Wavefront Sensor %s located at %s\n', h.Instrument_Name, resourceName);
                fprintf('Manufacturer:      %s\n', str1.ToString); 
                fprintf('Instrument Name:   %s\n', h.Instrument_Name);
                fprintf('Serial Number WFS: %s\n', h.Serial_Number);
                fprintf('Serial Number Cam: %s\n', str4.ToString);

                [retVal, h.MLA_Count] = h.deviceNET.GetMlaCount(); %#ok<ASGLU> 
                if h.MLA_Count > 1
                    tmpStr = 's are';
                else
                    tmpStr = ' is';
                end
                fprintf('%d Multi-Lens Array%s available for this instrument\n', h.MLA_Count, tmpStr);

                [retVal, h.Master_Gain_Min, h.Master_Gain_Max] = h.deviceNET.GetMasterGainRange(); %#ok<ASGLU> 
                h.Connected = true;
            else % Device is already connected
                error('Device is already connected.')
            end
        end

        % =================================================================
        function disconnect(h) 
        % Disconnect device     
            if h.Connected
                try
                    h.deviceNET.Dispose();
                    h.Connected = false;
                    h.Initialized = false;
                catch Exception
                    error('Unable to disconnect the device %s located at %s', h.Instrument_Name, h.Resource_Name);
                end
                fprintf('%s located at %s is disconnected successfully!\n', h.Instrument_Name, h.Resource_Name);
            else % Cannot disconnect because device not connected
                error('Device not connected.')
            end    
        end

        % =================================================================
        function configureDevice(h, imgsize)
        % set the camera to a pre-defined resolution (pixels x pixels). This image size needs to fit the beam size and pupil size
            if nargin < 2
                if bitand(h.Device_ID, h.deviceNET.DeviceOffsetWFS30)
                    imgsize = h.CAM_RES_WFS30_1936;
                end
            elseif bitand(h.Device_ID, h.deviceNET.DeviceOffsetWFS30)
                % check limits
                if mod(imgsize,1) || imgsize < 0 || imgsize > h.CAM_RES_WFS30_MAX_IDX
                    error('Pre-defined image size index for WFS30 sensor should be an integer in the range [0;%d]\n', h.CAM_RES_WFS30_MAX_IDX);
                end
            end
            [retVal, spotsX, spotsY] = h.deviceNET.ConfigureCam(h.PIXEL_FORMAT_MONO8, imgsize); %#ok<ASGLU> 
            fprintf('Camera is configured to detect %d x %d lenslet spots.\n', spotsX, spotsY);
            [RetVal, Exposure_Time_Min, Exposure_Time_Max, Exposure_Time_Incr] = h.deviceNET.GetExposureTimeRange(); %#ok<ASGLU> 
            h.Exposure_Time_Min_s  = Exposure_Time_Min / 1000;
            h.Exposure_Time_Max_s  = Exposure_Time_Max / 1000;
            h.Exposure_Time_Incr_s = Exposure_Time_Incr / 1000;
        end

        % =================================================================
        function setReferencePlane(h, refPlane)
        % set WFS reference plane
            if nargin < 2
                refPlane = h.WFS_REF_INTERNAL;
            else 
                if isnumeric(refPlane)
                    if mod(refPlane,1) || refPlane < 0 || refPlane > 1
                        error('Reference plane constant should be an integer in the range [0;1]');
                    end
                elseif ischar(refPlane)
                    if strcmpi(refPlane,'internal')
                        refPlane = h.WFS_REF_INTERNAL;
                    elseif strcmpi(refPlane,'user')
                        refPlane = h.WFS_REF_USER;
                    else
                        error('Reference plane constant should be either ''internal'' or ''user''');
                    end
                end
            end
            h.deviceNET.SetReferencePlane(refPlane);
        end        

        % =================================================================
        function adjustImageBrightness(h)
        % use the autoexposure feature to get a well exposed camera image. Repeat image reading in case of badly saturated image. Suited exposure time and gain settings are adjusted within the function TakeSpotfieldImageAutoExpos()
            sampleImageReadings = 10;
            for ks = 1:sampleImageReadings
                % take a camera image with auto exposure, note that there may several function calls required to get an optimal exposed image
                [ RetVal, Exposure_Time_Act, Master_Gain_Act] = h.deviceNET.TakeSpotfieldImageAutoExpos(); %#ok<ASGLU> 
                [ RetVal, Device_Status] = h.deviceNET.GetStatus(); %#ok<ASGLU> 
                if bitand(Device_Status, h.deviceNET.StatBitHighPower)
                    fprintf('Try %d. Power too high!\n', ks);
                elseif bitand(Device_Status, h.deviceNET.StatBitLowPower)
                    fprintf('Try %d. Power too low!\n', ks);
                elseif bitand(Device_Status, h.deviceNET.StatBitHighAmbientLight)
                    fprintf('Try %d. High ambient light!\n', ks);
                else
                    fprintf('Try %d. All OK! Exposure = %f; Gain = %f\n', ks, Exposure_Time_Act, Master_Gain_Act);
                    break;
                end
            end
        end

        % =================================================================
        function cutImageNoiseFloor(h, Limit)
        % Sets all pixels with intensities Limit to zero which cuts the noise floor of the camera.
            RetVal = h.deviceNET.CutImageNoiseFloor(int32(Limit)); %#ok<*NASGU> 
        end

        % =================================================================
        function setAveraging(h, val)
        % Sets number of images for averaging
            if mod(val,1) || val < 0 || val > 100
                error('Number of images for averaging should be an integer in the range [0;100]\n');
            end
            [ RetVal, Averaged_Data_Ready] = h.deviceNET.AverageImage(int32(val)); %#ok<ASGLU> 
        end

        % =================================================================
        function setAveragingRolling(h, val, reset)
        % Sets number of images for rolling averaging
            if nargin < 3
                reset = 1;
            end
            if mod(val,1) || val < 0 || val > 100
                error('Number of images for rolling averaging should be an integer in the range [0;100]\n');
            end
            RetVal = h.deviceNET.AverageImageRolling(int32(val),int32(reset));  
        end

        % =================================================================
        function takeSpotfieldImage(h)
        % Takes new image
            h.deviceNET.TakeSpotfieldImage();
        end
    end % methods (Sealed)

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% M E T H O D S - DEPENDENT, REQUIRE SET/GET
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

    methods

        % =================================================================
        function set.Pupil(h, val)
        % define pupil size and position, Zernike results are related to pupil
            if val(1) < h.PUPIL_CTR_MIN_MM || val(2) < h.PUPIL_CTR_MIN_MM || val(1) > h.PUPIL_CTR_MAX_MM || val(2) > h.PUPIL_CTR_MAX_MM
                error('Pupil center position should be in the range [%.1f;%.1f]!', h.PUPIL_CTR_MIN_MM, h.PUPIL_CTR_MAX_MM);
            end
            if val(3) < h.PUPIL_DIA_MIN_MM || val(4) < h.PUPIL_DIA_MIN_MM || val(3) > h.PUPIL_DIA_MAX_MM || val(4) > h.PUPIL_DIA_MAX_MM
                error('Pupil diameter should be in the range [%.1f;%.1f]!', h.PUPIL_DIA_MIN_MM, h.PUPIL_DIA_MAX_MM);
            end
            tmp = num2cell(val);
            [ Pupil_Center_X_mm, Pupil_Center_Y_mm, Pupil_Diameter_X_mm, Pupil_Diameter_Y_mm] = deal(tmp{:});
            h.deviceNET.SetPupil( Pupil_Center_X_mm, Pupil_Center_Y_mm, Pupil_Diameter_X_mm, Pupil_Diameter_Y_mm);
            h.Pupil_Defined = true;
        end

        % =================================================================
        function val = get.Pupil(h)
            if h.Pupil_Defined
                [RetVal, Pupil_Center_X_mm, Pupil_Center_Y_mm, Pupil_Diameter_X_mm, Pupil_Diameter_Y_mm] = h.deviceNET.GetPupil(); %#ok<ASGLU> 
                val = [Pupil_Center_X_mm, Pupil_Center_Y_mm, Pupil_Diameter_X_mm, Pupil_Diameter_Y_mm];
            else
                val = [nan,nan];
            end
        end

        % =================================================================
        function set.Beam_Centroid(~, ~)
            error('You cannot set the Beam Centroid parameter directly!\n');            
        end

        % =================================================================
        function val = get.Beam_Centroid(h)
            [retVal, ctrX, ctrY, diaX, diaY] = h.deviceNET.CalcBeamCentroidDia(); %#ok<ASGLU> 
            val = [ctrX, ctrY, diaX, diaY];
        end

        % =================================================================
        function set.Spotfield_Image(~, ~)
            error('You cannot set the Spotfield_Image parameter directly!\n');            
        end

        % =================================================================
        function val = get.Spotfield_Image(h)
            ImageBuf = NET.createArray('System.Byte',h.deviceNET.ImageBufferSize);
            h.deviceNET.TakeSpotfieldImage();
            [retVal, Rows, Columns] = h.deviceNET.GetSpotfieldImageCopy(ImageBuf); %#ok<ASGLU> 
            uint8ImageBuf = uint8(ImageBuf);
            val = reshape(uint8ImageBuf(1:Rows*Columns),Columns, Rows);
        end

        % =================================================================
        function set.Zernike(~, ~)
            error('You cannot set the Zernike parameter directly!\n');            
        end

        % =================================================================
        function val = get.Zernike(h)
            Calculate_Diameters = 0; % don't calculate spot diameters
            h.deviceNET.CalcSpotsCentrDiaIntens(int32(h.Dynamic_Noise_Cut), int32(Calculate_Diameters));

            h.deviceNET.CalcSpotToReferenceDeviations(int32(h.Cancel_Wavefront_Tilt));

            Array_Zernike_um = NET.createArray('System.Single',h.maxZernikeModes+1); % Zernike modes will be here
            Array_Zernike_Orders_um = NET.createArray('System.Single',h.maxZernikeModes+1); % Zernike RMS variations will be here
            [RetVal, Zernike_Orders, RoC_mm_] = h.deviceNET.ZernikeLsf(Array_Zernike_um, Array_Zernike_Orders_um); %#ok<ASGLU> 
            h.Zernike_Orders_Calculated = int32(Zernike_Orders);
            sngArray_Zernike_um = single(Array_Zernike_um);
            sngArray_Zernike_Orders_um = single(Array_Zernike_Orders_um);
            val.Zernike = sngArray_Zernike_um(1+(1:h.deviceNET.ZernikeModes(h.Zernike_Order+1)));
            val.Zernike_Orders = sngArray_Zernike_Orders_um(1:h.Zernike_Order+1);
            val.RoC_mm = RoC_mm_;
        end
        
        % =================================================================
        function set.Wavefront(~, ~)
            error('You cannot set the Wavefront parameter directly!\n');            
        end

        % =================================================================
        function val = get.Wavefront(h)
            Calculate_Diameters = 0; % don't calculate spot diameters
            h.deviceNET.CalcSpotsCentrDiaIntens(int32(h.Dynamic_Noise_Cut), int32(Calculate_Diameters));

            h.deviceNET.CalcSpotToReferenceDeviations(int32(h.Cancel_Wavefront_Tilt));

            Wavefront_Type = int32(0); % WAVEFRONT_MEAS = 0
            Limit_to_Pupil = int32(1); 
            Array_Wavefront = NET.createArray('System.Single', h.deviceNET.MaxSpotY, h.deviceNET.MaxSpotX );
            h.deviceNET.CalcWavefront(Wavefront_Type, Limit_to_Pupil, Array_Wavefront);

            [RetVal, Min, Max, Diff, Mean, RMS, Weighted_RMS] = h.deviceNET.CalcWavefrontStatistics(); %#ok<ASGLU> 
            val = struct('Min', Min, 'Max', Max, 'Diff', Diff, 'Mean', Mean, 'RMS', RMS, 'Weighted_RMS', Weighted_RMS);
        end

        % =================================================================
        function set.FourierOptometric(~, ~)
            error('You cannot set the FourierOptometric parameter directly!\n');            
        end

        % =================================================================
        function val = get.FourierOptometric(h)
            h.Zernike; % Function WFS_ZernikeLsf is required to run prior to the calculation of the Fourier and Optometric parameters
            [RetVal, Fourier_M, Fourier_J0, Fourier_J45, Opto_Sphere, ...
                Opto_Cylinder, Opto_Axis_deg] = h.deviceNET.CalcFourierOptometric( ...
                h.Zernike_Orders_Calculated, h.Fourier_Order); %#ok<ASGLU> 
            val = struct('Fourier_M', Fourier_M, ...
                'Fourier_J0', Fourier_J0, 'Fourier_J45', Fourier_J45, ...
                'Opto_Sphere', Opto_Sphere, 'Opto_Cylinder', Opto_Cylinder, ...
                'Opto_Axis_deg', Opto_Axis_deg);
        end

        % =================================================================
        function set.Black_Level_Offset(h, val)
            % check limits
            if mod(val,1) || val < 0 || val > 255
                error('Black_Level_Offset value should be an integer in the range [0;255]\n');
            end
            RetVal = h.deviceNET.SetBlackLevelOffset(int32(val));  
        end

        % =================================================================
        function val = get.Black_Level_Offset(h)
            [RetVal, val] = h.deviceNET.GetBlackLevelOffset();  %#ok<ASGLU> 
        end

        % =================================================================
        function set.Exposure_Time(h, val)
            % check limits
            if val < h.Exposure_Time_Min_s || val > h.Exposure_Time_Max_s
                error('Exposure time value should be in the range [%.6f;%.6f] seconds\n', h.Exposure_Time_Min_s, h.Exposure_Time_Max_s);
            end
            [RetVal, Exposure_Time_Act] = h.deviceNET.SetExposureTime(val*1000);  %#ok<ASGLU> 
        end

        % =================================================================
        function val = get.Exposure_Time(h)
            [RetVal, Exposure_Time_Act_ms] = h.deviceNET.GetExposureTime();  %#ok<ASGLU> 
            val = Exposure_Time_Act_ms / 1000;
        end

        % =================================================================
        function set.Master_Gain(h, val)
            % check limits
            if val < h.Master_Gain_Min || val > h.Master_Gain_Max
                error('Master_Gain value should be in the range [%.2f;%.2f]\n', h.Master_Gain_Min, h.Master_Gain_Max);
            end
            [RetVal, Master_Gain_Act] = h.deviceNET.SetMasterGain(val);  %#ok<ASGLU> 
        end

        % =================================================================
        function val = get.Master_Gain(h)
            [RetVal, val] = h.deviceNET.GetMasterGain();  %#ok<ASGLU> 
        end

    end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% M E T H O D S  (STATIC) - load DLLs, get a list of devices
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

    methods (Static)

        function loaddlls() % Load DLLs
            if ~exist(thorlabswfs.WFSCLASSNAME,'class')
                try   % Load in DLLs if not already loaded
                    NET.addAssembly([thorlabswfs.DLLPATHDEFAULT,thorlabswfs.WFSDLL]);
                catch % DLLs did not load
                    error('Unable to load .NET assembly %s from the folder %s',thorlabswfs.WFSDLL,thorlabswfs.DLLPATHDEFAULT)
                end
            end    
        end 

    end % methods (Static)

end