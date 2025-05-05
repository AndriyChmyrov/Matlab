classdef flipper < handle 
    % Matlab class to control Thorlabs MFF101 flippers via Kinesis USB connection
    % It is a 'wrapper' to control Thorlabs devices via the Thorlabs .NET DLLs.
    %
    % Instructions:
    % Download the Kinesis DLLs from the Thorlabs website from:
    % https://www.thorlabs.com/software_pages/ViewSoftwarePage.cfm?Code=Motion_Control
    % Make sure to use x64 version of the Kinesis if you have x64 Matlab
    % Edit KINESISPATHDEFAULT below to point to the location of the DLLs
    % Connect your MFF10X Motorized Filter Flip Mounts to the PC USB port
    % Check with the Thorlabs Kinesis software that the shutter is operational
    %
    % Example:
    % fllist = flipper.listdevices  % List connected devices
    % fl1 = flipper                 % Create a flipper object  
    % fl2 = flipper                 % Create a flipper object  
    % fl1.connect(fllist{1})        % Connect the first flipper object to the first device in the list
    % fl2.connect('37007238')       % Connect the second flipper object to a device with a serial number 37007238
    % fl1.position                  % Get current position of the flipper: 1 (down) or 2 (up)
    % fl1.position = 2              % Set flipper to position 2 (up)
    % fl1.state                     % Get flipper state: 'Idle' / 'Moving'
    % fl1.isconnected               % Check if the flipper is connected
    % fl1.reset                     % Reset the flipper (not sure what is done)
    % fl1.disconnect                % Disconnect device
    %
    % Author: Andriy Chmyrov 
    % Helmholtz Zentrum Muenchen, Deutschland
    % Email: andriy.chmyrov@helmholtz-muenchen.de
    % 
    % based on a code of Julan A.J. Fells
    % Dept. Engineering Science, University of Oxford, Oxford OX1 3PJ, UK
    % Email: julian.fells@emg.ox.ac.uk (please email issues and bugs)
    % Website: http://wwww.eng.ox.ac.uk/smp
    %
    % Version History:
    % 1.0 05 May 2025 First Release
    
    
    properties (Constant, Hidden)
       % path to DLL files (edit as appropriate)
       KINESISPATHDEFAULT='C:\Program Files\Thorlabs\Kinesis\';

       % DLL files to be loaded
       DEVICEMANAGERDLL = 'Thorlabs.MotionControl.DeviceManagerCLI.dll';
       GENERICMOTORDLL  = 'Thorlabs.MotionControl.GenericMotorCLI.dll';
       FLIPPERDLL       = 'Thorlabs.MotionControl.FilterFlipperCLI.DLL';  
       DEVICEMANAGERCLASSNAME = 'Thorlabs.MotionControl.DeviceManagerCLI.DeviceManagerCLI'
       GENERICMOTORCLASSNAME  = 'Thorlabs.MotionControl.GenericMotorCLI.GenericMotorCLI';
       FLIPPERCLASSNAME       = 'Thorlabs.MotionControl.FilterFlipperCLI.FilterFlipper';            
       
       % Default intitial parameters 
       TPOLLING = 250;          % Default polling time, in ms
       TIMEOUTSETTINGS = 5000;  % Default timeout time for settings change
    end

    properties (Hidden)
        assemblyObj;
    end
    
    properties 
       % These properties are within Matlab wrapper 
       serialnumber;                % Device serial number
       prefix;                      % Device prefix
    end

    properties (Dependent)
        state;
        position;
        isconnected;
    end
    
    properties (Hidden)
       % These are properties within the .NET environment. 
       deviceNET;                   % Device object within .NET
       flipperSettingsNET;          % shutterSettings within .NET
       currentDeviceSettingsNET;    % currentDeviceSetings within .NET
       deviceInfoNET;               % deviceInfo within .NET
       initialized = false;         % initialization flag
    end
    
    methods

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% M E T H O D S - CONSTRUCTOR/DESCTRUCTOR
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        
        % ====================================================================
        function h = flipper()  % Constructor - Instantiate shutter object
            flipper.loaddlls; % Load DLLs (if not already loaded)
            serialNumbers = h.listdevices();    % Use this call to build a device list in case not invoked beforehand
            if isempty(serialNumbers)
                error('No compatible Thorlabs MFF Flipper devices found!');
            end
        end
        
        % ====================================================================
        function delete(h)  % Destructor 
            if ~isempty(h.deviceNET)
                try 
                    disconnect(h);
                catch
                end
            end
        end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% M E T H O D S - DEPENDENT, REQUIRE SET/GET
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

        
        % ====================================================================
        function res = get.state(h)
            res = char(h.deviceNET.State());
        end

        % ====================================================================
        function set.state(~,~)
            error('The property State can have values: ''Idle'', ''Moving'', etc. You cannot set the State property directly!\n');
        end
        
        % ====================================================================
        function res = get.position(h) %#ok<MANU>
            res = cast(eval('h.deviceNET.Position'),'double'); %#ok<EVLCS>
        end

        % ====================================================================
        function set.position(h,new_position)
            h.deviceNET.SetPosition(new_position,0); % 0 - does not wait for movement to finish, returns State = 'Moving'
            % h.deviceNET.SetPosition(new_position,800); % use timeout 800 ms for movement to be finished
        end

        % ====================================================================
        function res = get.isconnected(h)
            res = h.deviceNET.IsConnected();
        end
        
        % ====================================================================
        function set.isconnected(~,~)
            error('You cannot set the IsConnected property directly!\n');
        end

    end
        
 %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
 % M E T H O D S (Sealed) - INTERFACE IMPLEMENTATION
 %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

    methods (Sealed)
 
        % ====================================================================
        function connect(h,serialNo)  % Connect device
            if ~h.initialized
                if isnumeric(serialNo) 
                    serialNo = num2str(serialNo);
                end
                if str2double(serialNo(1:2)) == double(Thorlabs.MotionControl.FilterFlipperCLI.FilterFlipper.DevicePrefix)
                    % Serial number corresponds to a MFF101 
                    h.deviceNET = Thorlabs.MotionControl.FilterFlipperCLI.FilterFlipper.CreateFilterFlipper(serialNo);
                else
                    % Serial number is not recognized
                    error('Thorlabs Flipper not recognised');
                end     
                h.deviceNET.Connect(serialNo);          % Connect to device via .NET interface
                try
                    if ~h.deviceNET.IsSettingsInitialized() % Wait for IsSettingsInitialized via .NET interface
                        h.deviceNET.WaitForSettingsInitialized(h.TIMEOUTSETTINGS);
                    end
                    if ~h.deviceNET.IsSettingsInitialized() % Cannot initialise device
                        error(['Unable to initialise device ', char(serialNo)]);
                    end
                    h.deviceNET.StartPolling(h.TPOLLING);   % Start polling via .NET interface
                    h.deviceNET.EnableDevice();             % Enable the channel otherwise any move is ignored 
                    h.serialnumber = char(h.deviceNET.DeviceID);   % update serial number
                    h.prefix = str2double(h.serialnumber(1:2));    % save device prefix, for distinguishing between KSC101 and TSC001

                    assemblies = System.AppDomain.CurrentDomain.GetAssemblies;
                    asmname = 'Thorlabs.MotionControl.DeviceManagerCLI';
                    asmidx = find(arrayfun(@(n) strncmpi(char(assemblies.Get(n-1).FullName), asmname, length(asmname)), 1:assemblies.Length));

                    settings_enum = assemblies.Get(asmidx-1).GetType('Thorlabs.MotionControl.DeviceManagerCLI.DeviceConfiguration+DeviceSettingsUseOptionType');
                    UseDeviceSettings_enumName = 'UseDeviceSettings';
                    UseDeviceSettings_enumIndx = find(arrayfun(@(n) strncmpi(char(settings_enum.GetEnumValues.Get(n-1)), UseDeviceSettings_enumName , length(UseDeviceSettings_enumName)), 1:settings_enum.GetEnumValues.GetLength(0)));
                    UseDeviceSettings = settings_enum.GetEnumValues().Get(UseDeviceSettings_enumIndx-1);

                    h.flipperSettingsNET = h.deviceNET.GetDeviceConfiguration(serialNo, UseDeviceSettings); % Get filterSettings via .NET interface
                catch err% Cannot initialise device
                    error(['Unable to initialise device ',char(serialNo)]);
                end
                fprintf('Flipper with S/N %s is connected successfully!\n',h.serialnumber);
            else % Device is already connected
                error('Device is already connected.')
            end
        end
        
        % ====================================================================
        function disconnect(h) % Disconnect device     
            if h.isconnected
                try
                    h.deviceNET.StopPolling();  % Stop polling device via .NET interface
                    h.deviceNET.DisableDevice();% Disables this device via .NET interface
                    h.deviceNET.Disconnect(true);   % Disconnect device via .NET interface
                catch
                    error(['Unable to disconnect device',h.serialnumber]);
                end
                h.initialized = false;
                fprintf('Flipper with S/N %s is disconnected successfully!\n',h.serialnumber);
            else % Cannot disconnect because device not connected
                error('Device not connected.')
            end
        end
        
        % ====================================================================
        function reset(h,serialNo)    % Reset device
            h.deviceNET.ResetConnection(serialNo) % Reset connection via .NET interface
        end

        % ====================================================================
        function res = status(h)
            h.deviceNET.RequestStatus(); % in principle excessive as polling is enabled
            res = h.deviceNET.GetStatusBits();
        end

    end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% M E T H O D S   (STATIC) - load DLLs, get a list of devices
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    
    methods (Static)
        
        % ====================================================================
        function serialNumbers = listdevices()  % Read a list of serial number of connected devices
            shutter.loaddlls; % Load DLLs
            Thorlabs.MotionControl.DeviceManagerCLI.DeviceManagerCLI.BuildDeviceList();  % Build device list
            serialNumbersNet = Thorlabs.MotionControl.DeviceManagerCLI.DeviceManagerCLI.GetDeviceList(Thorlabs.MotionControl.FilterFlipperCLI.FilterFlipper.DevicePrefix); % Get device list
            serialNumbers = cell(ToArray(serialNumbersNet)); % Convert serial numbers to cell array
        end
        
        % ====================================================================
        function loaddlls() % Load DLLs
            if ~exist(flipper.FLIPPERCLASSNAME,'class')
                try   % Load in DLLs if not already loaded
                    NET.addAssembly([flipper.KINESISPATHDEFAULT,flipper.DEVICEMANAGERDLL]);
                    NET.addAssembly([flipper.KINESISPATHDEFAULT,flipper.GENERICMOTORDLL]);
                    NET.addAssembly([flipper.KINESISPATHDEFAULT,flipper.FLIPPERDLL]); 
                catch % DLLs did not load
                    error('Unable to load .NET assemblies for Thorlabs Kinesis software')
                end
            end    
        end 
        
    end
    
end