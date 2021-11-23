classdef shutter < handle 
    % Matlab class to control Thorlabs SH05 shutters via Kinesis K-cube KSC101 
    % It is a 'wrapper' to control Thorlabs devices via the Thorlabs .NET DLLs.
    %
    % Instructions:
    % Download the Kinesis DLLs from the Thorlabs website from:
    % https://www.thorlabs.com/software_pages/ViewSoftwarePage.cfm?Code=Motion_Control
    % Make sure to use x64 version of the Kinesis if you have x64 Matlab
    % Edit KINESISPATHDEFAULT below to point to the location of the DLLs
    % Connect your KSC101 solenoid controller to the PC USB port and switch it on
    % Check with the Thorlabs Kinesis software that the shutter is operational
    %
    % Example:
    % shlist = shutter.listdevices  % List connected devices
    % sh1 = shutter                 % Create a shutter object  
    % sh2 = shutter                 % Create a shutter object  
    % sh1.connect(shlist{1})        % Connect the first shutter object to the first device in the list
    % sh2.connect('68250440')       % Connect the second shutter object to a device with a serial number 68250440
    % sh1.operatingmode             % Get current operating mode
    % sh1.operatingmode='manual'    % Set operating mode to Manual
    % sh1.operatingstate            % Get current operating state
    % sh1.operatingstate='active'   % Set operating state to Active, which in Manual mode opens the shutter
    % sh1.operatingstate='inactive' % Set operating state to Inactive, which in Manual mode closes the shutter
    % sh1.state                     % Get shutter state: 'Open' / 'Closed'
    % sh1.disconnect                % Disconnect device
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
    % Known Issues:
    % 1. If shutter object gets deleted or corrupted it is sometimes necessary to
    % restart Matlab
    %
    % Version History:
    % 1.0 01 July 2021 First Release
    
    
    properties (Constant, Hidden)
       % path to DLL files (edit as appropriate)
       KINESISPATHDEFAULT='C:\Program Files\Thorlabs\Kinesis\';

       % DLL files to be loaded
       DEVICEMANAGERDLL = 'Thorlabs.MotionControl.DeviceManagerCLI.dll';
       GENERICMOTORDLL  = 'Thorlabs.MotionControl.GenericMotorCLI.dll';
       SOLENOIDDLL      = 'Thorlabs.MotionControl.KCube.SolenoidCLI.dll';  
       DEVICEMANAGERCLASSNAME = 'Thorlabs.MotionControl.DeviceManagerCLI.DeviceManagerCLI'
       GENERICMOTORCLASSNAME  = 'Thorlabs.MotionControl.GenericMotorCLI.GenericMotorCLI';
       SOLENOIDCLASSNAME      = 'Thorlabs.MotionControl.KCube.SolenoidCLI.KCubeSolenoid';            
       
       % Default intitial parameters 
       TPOLLING = 250;          % Default polling time, in ms
       TIMEOUTSETTINGS = 5000;  % Default timeout time for settings change
    end

    properties (Hidden)
        assemblyObj;
        OPSTATE;
        OPSTATE_ACTIVE;
        OPSTATE_INACTIVE;
        OPMODE;
        OPMODE_MANUAL;
        OPMODE_SINGLETOGGLE;
        OPMODE_AUTOTOGGLE;
        OPMODE_TRIGGERED;
    end
    
    properties 
       % These properties are within Matlab wrapper 
       serialnumber;                % Device serial number
       controllername;              % Controller Name
       controllerdescription        % Controller Description
       stagename;                   % Stage Name
    end

    properties (Dependent)
        frontpanellock;
        operatingmode;
        operatingstate;
        state;
        isconnected;
    end
    
    properties (Hidden)
       % These are properties within the .NET environment. 
       deviceNET;                   % Device object within .NET
       shutterSettingsNET;          % shutterSettings within .NET
       currentDeviceSettingsNET;    % currentDeviceSetings within .NET
       deviceInfoNET;               % deviceInfo within .NET
       initialized = false;         % initialization flag
    end
    
    methods

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% M E T H O D S - CONSTRUCTOR/DESCTRUCTOR
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        
        % ====================================================================
        function h = shutter()  % Constructor - Instantiate shutter object
            shutter.loaddlls; % Load DLLs (if not already loaded)
            serialNumbers = h.listdevices();    % Use this call to build a device list in case not invoked beforehand
            if isempty(serialNumbers)
                error('No compatible Thorlabs K-Cube devices found!');
            end
        end
        
        % ====================================================================
        function delete(h)  % Destructor 
            if ~isempty(h.deviceNET)
                try 
                    if h.isconnected
                        h.operatingstate = 'inactive';
                    end
                    disconnect(h);
                catch
                end
            end
        end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% M E T H O D S - DEPENDENT, REQUIRE SET/GET
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

        % ====================================================================
        function res = get.frontpanellock(h)
            h.deviceNET.RequestFrontPanelLocked();
            res = h.deviceNET.GetFrontPanelLocked();
        end

        % ====================================================================
        function set.frontpanellock(h, lockstate)
            if ~h.deviceNET.CanDeviceLockFrontPanel()
                disp('The device does not support front panel locking.')
            else
                if isnumeric(lockstate)
                    lockstate = logical(lockstate);
                end
                if islogical(lockstate)
                    h.deviceNET.SetFrontPanelLock(lockstate);
                end
            end
        end

        % ====================================================================
        function res = get.operatingmode(h)
            res = char(h.deviceNET.GetOperatingMode());
        end

        % ====================================================================
        function set.operatingmode(h, newmode)
            if isnumeric(newmode)
                newmodeNET = h.OPMODE{newmode+1};
            elseif (ischar(newmode) || isstring(newmode))
                if strcmpi(newmode,'manual')
                    newmodeNET = h.OPMODE_MANUAL;
                elseif strcmpi(newmode,'singletoggle')
                    newmodeNET = h.OPMODE_SINGLETOGGLE;
                elseif strcmpi(newmode,'autotoggle')
                    newmodeNET = h.OPMODE_AUTOTOGGLE;
                elseif strcmpi(newmode,'triggered')
                    newmodeNET = h.OPMODE_TRIGGERED;
                else
                    error('Operating mode not recognized!')
                end
            end
            h.deviceNET.SetOperatingMode(newmodeNET);
        end

        % ====================================================================
        function res = get.operatingstate(h)
            res = char(h.deviceNET.GetOperatingState());
        end

        % ====================================================================
        function set.operatingstate(h, newstate)
            if isnumeric(newstate)
                newstateNET = h.OPSTATE{newstate+1};
            elseif (ischar(newstate) || isstring(newstate))
                if strcmpi(newstate,'active')
                    newstateNET = h.OPSTATE_ACTIVE;
                elseif strcmpi(newstate,'inactive')
                    newstateNET = h.OPSTATE_INACTIVE;
                else
                    error('Operating state not recognized!')
                end
            end
            h.deviceNET.SetOperatingState(newstateNET);
        end
        
        % ====================================================================
        function res = get.state(h)
            res = char(h.deviceNET.GetSolenoidState());
        end

        % ====================================================================
        function set.state(~,~)
            error('You cannot set the State property directly!\n');
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
                if str2double(serialNo(1:2)) == double(Thorlabs.MotionControl.KCube.SolenoidCLI.KCubeSolenoid.DevicePrefix)
                    % Serial number corresponds to a KSC101 
                    h.deviceNET = Thorlabs.MotionControl.KCube.SolenoidCLI.KCubeSolenoid.CreateKCubeSolenoid(serialNo);
                else
                    % Serial number is not recognized
                    error('Thorlabs Shutter and K-Cube not recognised');
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
                    h.shutterSettingsNET = h.deviceNET.GetSolenoidConfiguration(serialNo); % Get shutterSettings via .NET interface
                    h.stagename    = char(h.shutterSettingsNET.DeviceSettingsName);% update stagename
                    h.currentDeviceSettingsNET = Thorlabs.MotionControl.KCube.SolenoidCLI.ThorlabsKCubeSolenoidSettings.GetSettings(h.shutterSettingsNET);     % Get currentDeviceSettings via .NET interface
                    h.deviceInfoNET = h.deviceNET.GetDeviceInfo();                    % Get deviceInfo via .NET interface
                    h.controllername = char(h.deviceInfoNET.Name); % update controleller name          
                    h.controllerdescription = char(h.deviceInfoNET.Description);   % update controller description

                    assemblies = System.AppDomain.CurrentDomain.GetAssemblies;
                    asmname = 'Thorlabs.MotionControl.KCube.SolenoidCLI';
                    asmidx = find(arrayfun(@(n) strncmpi(char(assemblies.Get(n-1).FullName), asmname, length(asmname)), 1:assemblies.Length));

                    % find required enum and its values
                    states_enum = assemblies.Get(asmidx-1).GetType('Thorlabs.MotionControl.KCube.SolenoidCLI.SolenoidStatus+OperatingStates');
                    inactive_enumName = 'Inactive';
                    inactive_enumIndx = find(arrayfun(@(n) strncmpi(char(states_enum.GetEnumValues.Get(n-1)), inactive_enumName , length(inactive_enumName)), 1:states_enum.GetEnumValues.GetLength(0)));
                    active_enumName = 'Active';
                    active_enumIndx = find(arrayfun(@(n) strncmpi(char(states_enum.GetEnumValues.Get(n-1)), active_enumName, length(active_enumName)), 1:states_enum.GetEnumValues.GetLength(0)));
                    h.OPSTATE_ACTIVE = states_enum.GetEnumValues().Get(active_enumIndx-1);
                    h.OPSTATE_INACTIVE = states_enum.GetEnumValues().Get(inactive_enumIndx-1);
                    h.OPSTATE = {h.OPSTATE_INACTIVE, h.OPSTATE_ACTIVE};

                    ehOpModes = assemblies.Get(asmidx-1).GetType('Thorlabs.MotionControl.KCube.SolenoidCLI.SolenoidStatus+OperatingModes');
                    h.OPMODE_MANUAL       = ehOpModes.GetEnumValues().Get(0);
                    h.OPMODE_SINGLETOGGLE = ehOpModes.GetEnumValues().Get(1);
                    h.OPMODE_AUTOTOGGLE   = ehOpModes.GetEnumValues().Get(2);
                    h.OPMODE_TRIGGERED    = ehOpModes.GetEnumValues().Get(3);
                    h.OPMODE = {h.OPMODE_MANUAL, h.OPMODE_SINGLETOGGLE, h.OPMODE_AUTOTOGGLE, h.OPMODE_TRIGGERED};
                catch err% Cannot initialise device
                    error(['Unable to initialise device ',char(serialNo)]);
                end
                fprintf('Shutter %s with S/N %s is connected successfully!\n',h.controllername,h.serialnumber);
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
                    h.deviceNET.Disconnect();   % Disconnect device via .NET interface
                catch
                    error(['Unable to disconnect device',h.serialnumber]);
                end
                h.initialized = false;
                fprintf('Shutter %s with S/N %s is disconnected successfully!\n',h.controllername,h.serialnumber);
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
            reshexflip = fliplr(dec2hex(res,4));
            if bitget(res,1)
                disp('Solenoid output is enabled');
            else
                disp('Solenoid output is disabled');
            end
            if reshexflip(4) == '2'
                disp('Solenoid interlock state is enabled');
            else
                disp('Solenoid interlock state is disabled');
            end
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
            serialNumbersNet = Thorlabs.MotionControl.DeviceManagerCLI.DeviceManagerCLI.GetDeviceList(Thorlabs.MotionControl.KCube.SolenoidCLI.KCubeSolenoid.DevicePrefix); % Get device list
            serialNumbers = cell(ToArray(serialNumbersNet)); % Convert serial numbers to cell array
        end
        
        % ====================================================================
        function loaddlls() % Load DLLs
            if ~exist(shutter.SOLENOIDCLASSNAME,'class')
                try   % Load in DLLs if not already loaded
                    NET.addAssembly([shutter.KINESISPATHDEFAULT,shutter.DEVICEMANAGERDLL]);
                    NET.addAssembly([shutter.KINESISPATHDEFAULT,shutter.GENERICMOTORDLL]);
                    NET.addAssembly([shutter.KINESISPATHDEFAULT,shutter.SOLENOIDDLL]); 
                catch % DLLs did not load
                    error('Unable to load .NET assemblies for Thorlabs Kinesis software')
                end
            end    
        end 
        
    end
    
end