classdef motor < handle 
    % Matlab class to control Thorlabs motorized translation/rotation stages
    % It is a 'wrapper' to control Thorlabs devices via the Thorlabs .NET DLLs.
    %
    % Instructions:
    % Download the Kinesis DLLs from the Thorlabs website from:
    % https://www.thorlabs.com/software_pages/ViewSoftwarePage.cfm?Code=Motion_Control
    % Make sure to use x64 version of the Kinesis if you have x64 Matlab
    %
    % Edit KINESISPATHDEFAULT below to point to the location of the DLLs
    % Connect your BBD30X/PRM1Z8/K10CR1 translation/rotation stage(s) to the PC USB port(if
    % using BBD30X/PRMZ8 also switch it on)
    %
    % Example for K10CR1 rotational stage:
    % mlist=motor.listdevices % List connected devices
    % mot = motor             % Create a motor object  
    % mot.connect(mlist{1})   % Connect the first devce in the list of devices
    % mot.home                % Home the device
    % mot.moveto(45)          % Move the device to the 45 degree setting
    % mot.moverel_deviceunit(-100000) % Move 100000 'clicks' backwards
    % mot.disconnect          % Disconnect device
    % clear mot               % Clear device object from memory
    %
    % Example for BBD302 controller with MLS203 translational stage
    % motXY = motor;          % create a motor object
    % motXY.connect('103205624') % connect to a controller with a serial number 103205624
    % motXY.enable            % enable all channels
    % motXY.ishomed           % check if channels are homed
    % motXY.home              % perform homing for all channels
    % motXY.position          % get the current position for all channels
    % motXY.moveto([15,25])   % move to position 15 mm on Ch1 and 25 mm on Ch2
    % motXY.maxvelocity = [10,50];   % set maxvelocity for movement to 10 mm/s for Ch1 and 50 mm/s for Ch2
    % motXY.acceleration = [500,500];% set acceleration to 500 mm/s2 for both channels
    % motXY.moveto([55,37.5]) % move to position [55 mm, 37.5], which is the center
    % motXY.disconnect        % disconnect the device
    % clear motXY             % Clear device object from memory
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
    %
    % Version History:
    % 2.0 16 Nov 2021 - added support of BBD30X motion controllers
    
    
    properties (Constant, Hidden)
       % path to DLL files (edit as appropriate)
       KINESISPATHDEFAULT = 'C:\Program Files\Thorlabs\Kinesis\'

       % DLL files to be loaded
       DEVICEMANAGERDLL='Thorlabs.MotionControl.DeviceManagerCLI.dll';
       DEVICEMANAGERCLASSNAME='Thorlabs.MotionControl.DeviceManagerCLI.DeviceManagerCLI'
       GENERICMOTORDLL='Thorlabs.MotionControl.GenericMotorCLI.dll';
       GENERICMOTORCLASSNAME='Thorlabs.MotionControl.GenericMotorCLI.GenericMotorCLI';
       DCSERVODLL='Thorlabs.MotionControl.KCube.DCServoCLI.dll';  
       DCSERVOCLASSNAME='Thorlabs.MotionControl.KCube.DCServoCLI.KCubeDCServo';            
       INTEGSTEPDLL='Thorlabs.MotionControl.IntegratedStepperMotorsCLI.dll' 
       INTEGSTEPCLASSNAME='Thorlabs.MotionControl.IntegratedStepperMotorsCLI.IntegratedStepperMotor.CageRotator';
       BRUSHLESSDLL='Thorlabs.MotionControl.Benchtop.BrushlessMotorCLI.dll';
       BRUSHLESSCLASSNAME='Thorlabs.MotionControl.Benchtop.BrushlessMotorCLI ';

       % Default intitial parameters 
       DEFAULTVEL=10;           % Default velocity
       DEFAULTACC=10;           % Default acceleration
       TPOLLING=250;            % Default polling time
       TIMEOUTSETTINGS=7000;    % Default timeout time for settings change
       TIMEOUTMOVE=100000;      % Default time out time for motor move
    end

    properties 
       % These properties are within Matlab wrapper 
       serialnumber;                % Device serial number
       controllername;              % Controller Name
       controllerdescription        % Controller Description
       stagename;                   % Stage Name
       acclimit;                    % Acceleration limit
       vellimit;                    % Velocity limit
    end

    properties (Dependent)
       isconnected;                 % Flag set if device connected
       position;                    % Position
       maxvelocity;                 % Maximum velocity limit
       minvelocity;                 % Minimum velocity limit
       acceleration;                % Acceleration
    end

    properties (Hidden)
       % These are properties within the .NET environment. 
       deviceNET;                   % Device object within .NET
       motorSettingsNET;            % motorSettings within .NET
       currentDeviceSettingsNET;    % currentDeviceSetings within .NET
       deviceInfoNET;               % deviceInfo within .NET
       prefix;                      % prefix of the serial number
       channel;                     % channels for multichannel controller
       controller;                  % controller of synchronous functionality (BBD30X only). 
       initialized = false;         % initialization flag
    end


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% M E T H O D S - CONSTRUCTOR/DESCTRUCTOR
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    methods

        % =================================================================
        function h = motor() % Constructor - Instantiate motor object
            motor.loaddlls; % Load DLLs (if not already loaded)
        end

        % =================================================================
        function delete(h) % Destructor 
            if ~isempty(h.deviceNET) && h.deviceNET.IsConnected()
                try
                    disconnect(h);
                catch
                end
            end
        end

    end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% M E T H O D S (Sealed) - INTERFACE IMPLEMENTATION
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

    methods (Sealed)

        % =================================================================
        function connect(h,serialNo)  % Connect device
            h.listdevices();    % Use this call to build a device list in case not invoked beforehand
            if ~h.initialized
                if isnumeric(serialNo) && isscalar(serialNo)
                    serialNo = int2str(serialNo);
                end
                h.prefix = int32(str2double(serialNo(1:end-6)));
                switch(h.prefix)
                    case Thorlabs.MotionControl.KCube.DCServoCLI.KCubeDCServo.DevicePrefix
                        % 27 - Serial number corresponds to a PRM1Z8
                        h.deviceNET = Thorlabs.MotionControl.KCube.DCServoCLI.KCubeDCServo.CreateKCubeDCServo(serialNo);   
                    case Thorlabs.MotionControl.IntegratedStepperMotorsCLI.CageRotator.DevicePrefix   
                        % 55 - Serial number corresponds to a K10CR1 
                        h.deviceNET = Thorlabs.MotionControl.IntegratedStepperMotorsCLI.CageRotator.CreateCageRotator(serialNo);
                    case Thorlabs.MotionControl.Benchtop.BrushlessMotorCLI.BenchtopBrushlessMotor.DevicePrefix103
                        % 103 - Serial number corresponds to BBD30X type devices 
                        h.deviceNET = Thorlabs.MotionControl.Benchtop.BrushlessMotorCLI.BenchtopBrushlessMotor.CreateBenchtopBrushlessMotor(serialNo);
                    otherwise % Serial number is not a PRM1Z8 or a K10CR1
                        error('Stage not recognised');
                end
                try
                    h.deviceNET.ClearDeviceExceptions();    % Clear device exceptions via .NET interface
                catch exception %#ok<NASGU> 
                end
                h.deviceNET.Connect(serialNo);          % Connect to device via .NET interface
                switch(h.prefix)
                    case {Thorlabs.MotionControl.KCube.DCServoCLI.KCubeDCServo.DevicePrefix,...
                            Thorlabs.MotionControl.IntegratedStepperMotorsCLI.CageRotator.DevicePrefix}
                        try
                            h.deviceInfoNET = h.deviceNET.GetDeviceInfo();                    % Get deviceInfo via .NET interface
                            if ~h.deviceNET.IsSettingsInitialized % Wait for IsSettingsInitialized via .NET interface
                                h.deviceNET.WaitForSettingsInitialized(h.TIMEOUTSETTINGS);
                            end
                            if ~h.deviceNET.IsSettingsInitialized % Cannot initialise device
                                error(['Unable to initialise device ',char(serialNo)]);
                            end
                            h.deviceNET.StartPolling(h.TPOLLING);   % Start polling via .NET interface
                            pause(0.1);
                            h.deviceNET.EnableDevice();
                            pause(0.1);
                            h.motorSettingsNET = h.deviceNET.LoadMotorConfiguration(serialNo); % Load motorSettings via .NET interface
                            h.stagename = char(h.motorSettingsNET.DeviceSettingsName);    % update stagename
                            h.currentDeviceSettingsNET = h.deviceNET.MotorDeviceSettings;     % Get currentDeviceSettings via .NET interface
                            h.acclimit = System.Decimal.ToDouble(h.currentDeviceSettingsNET.Physical.MaxAccnUnit);
                            h.vellimit = System.Decimal.ToDouble(h.currentDeviceSettingsNET.Physical.MaxVelUnit);
                            %MotDir=Thorlabs.MotionControl.GenericMotorCLI.Settings.RotationDirections.Forwards; % MotDir is enumeration for 'forwards'
                            %h.currentDeviceSettingsNET.Rotation.RotationDirection=MotDir;   % Set motor direction to be 'forwards#
                        catch % Cannot initialise device
                            error(['Unable to initialise device ',char(serialNo)]);
                        end
                    case Thorlabs.MotionControl.Benchtop.BrushlessMotorCLI.BenchtopBrushlessMotor.DevicePrefix103
                        % find a handle to already loaded .NET assembly with a name Thorlabs.MotionControl.DeviceManagerCLI
                        assemblies = System.AppDomain.CurrentDomain.GetAssemblies;
                        asmname = 'Thorlabs.MotionControl.DeviceManagerCLI';
                        asmidx = find(arrayfun(@(n) strncmpi(char(assemblies.Get(n-1).FullName), asmname, length(asmname)), 1:assemblies.Length));
                        % find required enum and its value with a name 'UseDeviceSettings'
                        settings_enum  = assemblies.Get(asmidx-1).GetType('Thorlabs.MotionControl.DeviceManagerCLI.DeviceConfiguration+DeviceSettingsUseOptionType');
                        settings_enumName = 'UseDeviceSettings';
                        settings_enumIndx = find(arrayfun(@(n) strncmpi(char(settings_enum.GetEnumValues.Get(n-1)), settings_enumName, length(settings_enumName)), 1:settings_enum.GetEnumValues.GetLength(0)));
                        % Initialize and return the Motherboard Configuration
                        h.deviceNET.GetMotherboardConfiguration(serialNo,settings_enum.GetEnumValues.Get(settings_enumIndx-1));
                        h.deviceInfoNET = h.deviceNET.GetDeviceInfo();                    % Get deviceInfo via .NET interface
                        h.controller = h.deviceNET.GetSyncController;
                        for km = 1:double(h.deviceInfoNET.NumChannels)
                            h.channel{km} = h.deviceNET.GetChannel(km);
                            try
                                h.channel{km}.Connect(serialNo);
                                if(~h.channel{km}.IsSettingsInitialized)
                                    h.channel{km}.WaitForSettingsInitialized(3000);
                                end
                            catch Exception %#ok<NASGU> 
                                    disp("Settings failed to initialize");
                            end
                            h.motorSettingsNET{km} = h.channel{km}.LoadMotorConfiguration(h.channel{km}.DeviceID); % Load motorSettings via .NET interface
                            h.channel{km}.StartPolling(h.TPOLLING);   % Start polling via .NET interface
                            pause(0.25);
                            h.stagename{km} = char(h.motorSettingsNET{km}.DeviceSettingsName);    % update stagename
                            h.currentDeviceSettingsNET{km} = h.channel{km}.MotorDeviceSettings();     % Get currentDeviceSettings via .NET interface
                            h.acclimit(km) = System.Decimal.ToDouble(h.currentDeviceSettingsNET{km}.Physical.MaxAccnUnit);
                            h.vellimit(km) = System.Decimal.ToDouble(h.currentDeviceSettingsNET{km}.Physical.MaxVelUnit);
                        end
                end
            else % Device is already connected
                error('Device is already connected.')
            end
            h.serialnumber   = char(h.deviceNET.DeviceID);        % update serial number
            h.controllername = char(h.deviceInfoNET.Name);        % update controleller name          
            h.controllerdescription = char(h.deviceInfoNET.Description);  % update controller description
            fprintf('%s with S/N %s is connected successfully!\n',h.controllerdescription,h.serialnumber);
            h.initialized = true;
        end

        % =================================================================
        function disconnect(h) % Disconnect device     
            if h.isconnected
                try
                    switch(h.prefix)
                        case {Thorlabs.MotionControl.KCube.DCServoCLI.KCubeDCServo.DevicePrefix,...
                              Thorlabs.MotionControl.IntegratedStepperMotorsCLI.CageRotator.DevicePrefix}
                            h.deviceNET.StopPolling();  % Stop polling device via .NET interface
                            h.deviceNET.Disconnect();   % Disconnect device via .NET interface
                        case Thorlabs.MotionControl.Benchtop.BrushlessMotorCLI.BenchtopBrushlessMotor.DevicePrefix103
                            % Serial number corresponds to a BBD302 
                            for km = 1:double(h.deviceInfoNET.NumChannels)
                                h.channel{km}.StopPolling();
                            end
                            h.deviceNET.ShutDown; % applies to all Benchtop devices
                    end
                catch Exception
                    error(['Unable to disconnect device',h.serialnumber]);
                end
                fprintf('%s with S/N %s is disconnected successfully!\n',h.controllerdescription,h.serialnumber);
            else % Cannot disconnect because device not connected
                error('Device not connected.')
            end    
            h.initialized = false;
        end

        % ====================================================================
        function reset(h,serialNo) % Reset device
            if nargin < 2
                serialNo = h.serialnumber;
            end
            switch(h.prefix)
                case {Thorlabs.MotionControl.KCube.DCServoCLI.KCubeDCServo.DevicePrefix,...
                      Thorlabs.MotionControl.IntegratedStepperMotorsCLI.CageRotator.DevicePrefix}
                    h.deviceNET.ClearDeviceExceptions();  % Clear exceptions vua .NET interface
                    h.deviceNET.ResetConnection(serialNo) % Reset connection via .NET interface
                case Thorlabs.MotionControl.Benchtop.BrushlessMotorCLI.BenchtopBrushlessMotor.DevicePrefix103
                    for km = 1:double(h.deviceInfoNET.NumChannels)
                        h.channel{km}.ClearDeviceExceptions();  % Clear exceptions vua .NET interface
                        h.channel{km}.ResetConnection(serialNo) % Reset connection via .NET interface
                    end
            end
        end

        % =================================================================
        function enable(h,chnum) % Enable channel (required for BBD30X type devices)
            switch(h.prefix)
                case Thorlabs.MotionControl.Benchtop.BrushlessMotorCLI.BenchtopBrushlessMotor.DevicePrefix103
                    if nargin == 2
                        chlist = chnum;
                    else
                        chlist = 1:double(h.deviceInfoNET.NumChannels);
                    end
                    for km = chlist
                        if ~h.channel{km}.IsEnabled
                            h.channel{km}.EnableDevice();
                            pause(0.5); % Needs a delay to give time for the device to be enabled
                        end
                    end
            end
        end

        % =================================================================
        function disable(h,chnum) % Disable channel (can be done for BenchtopBrushlessMotor type devices)
            switch(h.prefix)
                case Thorlabs.MotionControl.Benchtop.BrushlessMotorCLI.BenchtopBrushlessMotor.DevicePrefix103
                    if nargin == 2
                        chlist = chnum;
                    else
                        chlist = 1:double(h.deviceInfoNET.NumChannels);
                    end
                    for km = chlist
                        if h.channel{km}.IsEnabled
                            h.channel{km}.DisableDevice();
                            pause(0.1);
                        end
                    end
            end
        end

        % =================================================================
        function home(h,chnum) % Home device (must be done before any device move)
            switch(h.prefix)
                case {Thorlabs.MotionControl.KCube.DCServoCLI.KCubeDCServo.DevicePrefix,...
                      Thorlabs.MotionControl.IntegratedStepperMotorsCLI.CageRotator.DevicePrefix}
                    if ~h.deviceNET.NeedsHoming()
                        fprintf(2,'Device does not necessarily needs homing!\n');
                    end
                    workDone = h.deviceNET.InitializeWaitHandler(); % Initialise Waithandler for timeout
                    h.deviceNET.Home(workDone);                     % Home devce via .NET interface
                    h.deviceNET.Wait(h.TIMEOUTMOVE);                % Wait for move to finish
                case Thorlabs.MotionControl.Benchtop.BrushlessMotorCLI.BenchtopBrushlessMotor.DevicePrefix103
                    if nargin == 2
                        chlist = chnum;
                    else
                        chlist = 1:double(h.deviceInfoNET.NumChannels);
                    end
                    for km = chlist
                        if ~h.channel{km}.IsEnabled()
                            error('Channel %d is not enabled! Please enable it first before homing.',km)
                        end
                        if ~h.channel{km}.NeedsHoming()
                            fprintf(2,'Device does not necessarily needs homing!\n');
                        end
                        workDone{km} = h.channel{km}.InitializeWaitHandler(); %#ok<AGROW> % Initialise Waithandler for timeout
                        h.channel{km}.Home(workDone{km});                     % Home devce via .NET interface
                        h.channel{km}.Wait(h.TIMEOUTMOVE);                    % Wait for move to finish
                    end
            end
        end

        % =================================================================
        function res = ishomed(h,chnum) % Check if the device or the channel is homed
            switch(h.prefix)
                case {Thorlabs.MotionControl.KCube.DCServoCLI.KCubeDCServo.DevicePrefix,...
                      Thorlabs.MotionControl.IntegratedStepperMotorsCLI.CageRotator.DevicePrefix}
                        if ~h.deviceNET.NeedsHoming()
                            fprintf(2,'Device does not necessarily needs homing!\n');
                        end
                        status = h.deviceNET.Status(); 
                        res = status.IsHomed;
                case Thorlabs.MotionControl.Benchtop.BrushlessMotorCLI.BenchtopBrushlessMotor.DevicePrefix103
                    if nargin == 2
                        chlist = chnum;
                    else
                        chlist = 1:double(h.deviceInfoNET.NumChannels);
                    end
                    for km = chlist
                        chstatus = h.channel{km}.Status();  % Chech if the channel needs homing
                        if nargin == 2
                            res = chstatus.IsHomed;
                        else
                            res(km) = chstatus.IsHomed;
                        end
                    end
            end
        end

        % =================================================================
        function moveto(h,position)     % Move to absolute position
            switch(h.prefix)
                case {Thorlabs.MotionControl.KCube.DCServoCLI.KCubeDCServo.DevicePrefix,...
                      Thorlabs.MotionControl.IntegratedStepperMotorsCLI.CageRotator.DevicePrefix}
                    try
                        workDone=h.deviceNET.InitializeWaitHandler(); % Initialise Waithandler for timeout
                        h.deviceNET.MoveTo(position, workDone);       % Move devce to position via .NET interface
                        h.deviceNET.Wait(h.TIMEOUTMOVE);              % Wait for move to finish
                    catch % Device faile to move
                        error(['Unable to Move device ',h.serialnumber,' to ',num2str(position)]);
                    end
                case Thorlabs.MotionControl.Benchtop.BrushlessMotorCLI.BenchtopBrushlessMotor.DevicePrefix103
                    if length(position) ~= h.deviceInfoNET.NumChannels
                        error([int2str(h.deviceInfoNET.NumChannels) ' coordinates expected for the device ',h.controllername,' with serial number ',h.serialnumber,'!']);
                    end
                    for km = 1:double(h.deviceInfoNET.NumChannels)
                        workDone{km} = h.channel{km}.InitializeWaitHandler(); %#ok<AGROW> % Initialise Waithandler for timeout
                    end
                    for km = 1:double(h.deviceInfoNET.NumChannels)
                        h.channel{km}.MoveTo(position(km),workDone{km});
                    end
                    for km = 1:double(h.deviceInfoNET.NumChannels)
                        h.channel{km}.Wait(h.TIMEOUTMOVE);              % Wait for move to finish
                    end
            end
        end

        % =================================================================
        function moverel_deviceunit(h, noclicks)  % Move relative by a number of device clicks (noclicks)
            switch(h.prefix)
                case {Thorlabs.MotionControl.KCube.DCServoCLI.KCubeDCServo.DevicePrefix,...
                      Thorlabs.MotionControl.IntegratedStepperMotorsCLI.CageRotator.DevicePrefix}
                    if noclicks < 0   
                        % if noclicks is negative, move device in backwards direction
                        motordirection = Thorlabs.MotionControl.GenericMotorCLI.MotorDirection.Backward;
                        noclicks = abs(noclicks);
                    else            
                        % if noclicks is positive, move device in forwards direction
                        motordirection = Thorlabs.MotionControl.GenericMotorCLI.MotorDirection.Forward;
                    end             
                    % Perform relative device move via .NET interface
                    h.deviceNET.MoveRelative_DeviceUnit(motordirection,noclicks,h.TIMEOUTMOVE);
                case Thorlabs.MotionControl.Benchtop.BrushlessMotorCLI.BenchtopBrushlessMotor.DevicePrefix103
                    if length(noclicks) ~= h.deviceInfoNET.NumChannels
                        error([int2str(h.deviceInfoNET.NumChannels) ' clicks expected for the device ',h.controllername,' with serial number ',h.serialnumber,'!']);
                    end
                    for km = 1:double(h.deviceInfoNET.NumChannels)
                        if noclicks(km) < 0   
                            % if noclicks is negative, move device in backwards direction
                            motordirection = Thorlabs.MotionControl.GenericMotorCLI.MotorDirection.Backward;
                        else            
                            % if noclicks is positive, move device in forwards direction
                            motordirection = Thorlabs.MotionControl.GenericMotorCLI.MotorDirection.Forward;
                        end             
                        noclicks_ = abs(noclicks(km));
                        h.channel{km}.MoveRelative_DeviceUnit(motordirection,noclicks_,h.TIMEOUTMOVE);
                    end
            end
        end      

        % =================================================================
        function movecont(h, varargin)  % Set motor to move continuously
            switch(h.prefix)
                case {Thorlabs.MotionControl.KCube.DCServoCLI.KCubeDCServo.DevicePrefix,...
                      Thorlabs.MotionControl.IntegratedStepperMotorsCLI.CageRotator.DevicePrefix}
                    if (nargin>1) && (varargin{1})      % if parameter given (e.g. 1) move backwards
                        motordirection = Thorlabs.MotionControl.GenericMotorCLI.MotorDirection.Backward;
                    else                                % if no parametr given move forwards
                        motordirection = Thorlabs.MotionControl.GenericMotorCLI.MotorDirection.Forward;
                    end
                    h.deviceNET.MoveContinuous(motordirection); % Set motor into continous move via .NET interface
                case Thorlabs.MotionControl.Benchtop.BrushlessMotorCLI.BenchtopBrushlessMotor.DevicePrefix103
                    % !!! DIFFERENT SYNTAX !!!
                    % [1,1] - cont move forward, [-1,-1] - cont move backwards
                    if length(varargin{1}) ~= h.deviceInfoNET.NumChannels
                        error([int2str(h.deviceInfoNET.NumChannels) ' directions expected for the device ',h.controllername,' with serial number ',h.serialnumber,'!']);
                    end
                    for km = 1:double(h.deviceInfoNET.NumChannels)
                        if (varargin{1} == 1)      % move forwards
                            motordirection = Thorlabs.MotionControl.GenericMotorCLI.MotorDirection.Forward;
                        elseif (varargin{1} == -1) % move backwards
                            motordirection = Thorlabs.MotionControl.GenericMotorCLI.MotorDirection.Backward;
                        end
                        h.channel{km}.MoveContinuous(motordirection); % Set motor into continous move via .NET interface
                    end
            end
        end

        % =================================================================
        function stop(h,chnum) % Stop the motor moving (needed if set motor to continous)
            switch(h.prefix)
                case {Thorlabs.MotionControl.KCube.DCServoCLI.KCubeDCServo.DevicePrefix,...
                      Thorlabs.MotionControl.IntegratedStepperMotorsCLI.CageRotator.DevicePrefix}
                    h.deviceNET.Stop(h.TIMEOUTMOVE); % Stop motor movement via.NET interface
                case Thorlabs.MotionControl.Benchtop.BrushlessMotorCLI.BenchtopBrushlessMotor.DevicePrefix103
                    if nargin == 2
                        chlist = chnum;
                    else
                        chlist = 1:double(h.deviceInfoNET.NumChannels);
                    end
                    for km = chlist
                        h.controller.Stop(uint32(km));
                    end
            end
        end

        % =================================================================
        function setvelocity(h, varargin)  % Set velocity and acceleration parameters
            switch(h.prefix)
                case {Thorlabs.MotionControl.KCube.DCServoCLI.KCubeDCServo.DevicePrefix,...
                      Thorlabs.MotionControl.IntegratedStepperMotorsCLI.CageRotator.DevicePrefix}
                    velpars = h.deviceNET.GetVelocityParams(); % Get existing velocity and acceleration parameters
                    switch(nargin)
                        case 1  % If no parameters specified, set both velocity and acceleration to default values
                            velpars.MaxVelocity  = h.DEFAULTVEL;
                            velpars.Acceleration = h.DEFAULTACC;
                        case 2  % If just one parameter, set the velocity  
                            velpars.MaxVelocity  = varargin{1};
                        case 3  % If two parameters, set both velocitu and acceleration
                            velpars.MaxVelocity  = varargin{1};  % Set velocity parameter via .NET interface
                            velpars.Acceleration = varargin{2}; % Set acceleration parameter via .NET interface
                    end
                    if System.Decimal.ToDouble(velpars.MaxVelocity)>25  % Allow velocity to be outside range, but issue warning
                        warning('Velocity >25 deg/sec outside specification')
                    end
                    if System.Decimal.ToDouble(velpars.Acceleration)>25 % Allow acceleration to be outside range, but issue warning
                        warning('Acceleration >25 deg/sec2 outside specification')
                    end
                    h.deviceNET.SetVelocityParams(velpars); % Set velocity and acceleration paraneters via .NET interface
                case Thorlabs.MotionControl.Benchtop.BrushlessMotorCLI.BenchtopBrushlessMotor.DevicePrefix103
                    for km = 1:double(h.deviceInfoNET.NumChannels)
                        velpars = h.channel{km}.GetVelocityParams(); % Get existing velocity and acceleration parameters
                        switch(nargin)
                            case 1  % If no parameters specified, set both velocity and acceleration to default values
                                velpars.MaxVelocity = h.DEFAULTVEL;
                                velpars.Acceleration = h.DEFAULTACC;
                            case 2  % If just one parameter, set the velocity  
                                par1 = varargin{1};
                                velpars.MaxVelocity = par1(km);
                            case 3  % If two parameters, set both velocitu and acceleration
                                par1 = varargin{1};
                                par2 = varargin{2};
                                velpars.MaxVelocity  = par1(km);  % Set velocity parameter via .NET interface
                                velpars.Acceleration = par2(km); % Set acceleration parameter via .NET interface
                        end
                        if System.Decimal.ToDouble(velpars.MaxVelocity)>250  % Allow velocity to be outside range, but issue warning
                            warning('Velocity >250 mm/sec outside specification')
                        end
                        if System.Decimal.ToDouble(velpars.Acceleration)>2000 % Allow acceleration to be outside range, but issue warning
                            warning('Acceleration >2000 mm/sec2 outside specification')
                        end
                        h.channel{km}.SetVelocityParams(velpars); % Set velocity and acceleration paraneters via .NET interface
                    end
            end
        end

        % =================================================================
        function res = getstatus(h,chnum)
            switch(h.prefix)
                case Thorlabs.MotionControl.Benchtop.BrushlessMotorCLI.BenchtopBrushlessMotor.DevicePrefix103
                    if nargin == 2
                        chlist = chnum;
                    else
                        chlist = 1:double(h.deviceInfoNET.NumChannels);
                    end
                    for km = chlist
                        chstatus = h.channel{km}.Status;  % Check if the channel needs homing
                        if nargin == 2
                            res = chstatus;
                        elseif nargin == 1
                            res{km} = chstatus;
                        end
                    end                    
            end
        end

        % =================================================================
        function cleardeviceexceptions(h,chnum)
            switch(h.prefix)
                case Thorlabs.MotionControl.Benchtop.BrushlessMotorCLI.BenchtopBrushlessMotor.DevicePrefix103
                    if nargin == 2
                        chlist = chnum;
                    else
                        chlist = 1:double(h.deviceInfoNET.NumChannels);
                    end
                    for km = chlist
                        h.channel{km}.ClearDeviceExceptions;
                    end                    
            end
        end

    end % methods (Sealed)

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% M E T H O D S - DEPENDENT, REQUIRE SET/GET
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

    methods

        % =================================================================
        function set.acceleration(h, val)
            switch(h.prefix)
                case {Thorlabs.MotionControl.KCube.DCServoCLI.KCubeDCServo.DevicePrefix,...
                      Thorlabs.MotionControl.IntegratedStepperMotorsCLI.CageRotator.DevicePrefix}
                    % check physical limits
                    if val > h.acclimit
                        error('Requested acceleration is higher than the physical limit, which is %.2f',h.acclimit);
                    end
                    velpars = h.deviceNET.GetVelocityParams(); % Get existing velocity and acceleration parameters
                    velpars.Acceleration = val;
                    h.deviceNET.SetVelocityParams(velpars); % Set velocity and acceleration paraneters via .NET interface
                case Thorlabs.MotionControl.Benchtop.BrushlessMotorCLI.BenchtopBrushlessMotor.DevicePrefix103
                    for km = 1:double(h.deviceInfoNET.NumChannels)
                        % check physical limits
                        if val(km) > h.acclimit(km)
                            error('Requested acceleration is higher than the physical limit for Ch%d, which is %.2f',km,h.acclimit(km));
                        end
                        velpars = h.channel{km}.GetVelocityParams(); % Get existing velocity and acceleration parameters
                        velpars.Acceleration = val(km);
                        h.channel{km}.SetVelocityParams(velpars); % Set velocity and acceleration paraneters via .NET interface
                    end
            end
        end

        % =================================================================
        function val = get.acceleration(h)
            switch(h.prefix)
                case {Thorlabs.MotionControl.KCube.DCServoCLI.KCubeDCServo.DevicePrefix,...
                      Thorlabs.MotionControl.IntegratedStepperMotorsCLI.CageRotator.DevicePrefix}
                    velpars = h.deviceNET.GetVelocityParams(); % Get existing velocity and acceleration parameters
                    val = System.Decimal.ToDouble(velpars.Acceleration);
                case Thorlabs.MotionControl.Benchtop.BrushlessMotorCLI.BenchtopBrushlessMotor.DevicePrefix103
                    for km = 1:double(h.deviceInfoNET.NumChannels)
                        velocityparams{km} = h.channel{km}.GetVelocityParams();             %#ok<AGROW> % update velocity parameter
                        val(km) = System.Decimal.ToDouble(velocityparams{km}.Acceleration); %#ok<AGROW> % update acceleration parameter
                    end
            end
        end

        % =================================================================
        function set.maxvelocity(h, val)
            switch(h.prefix)
                case {Thorlabs.MotionControl.KCube.DCServoCLI.KCubeDCServo.DevicePrefix,...
                      Thorlabs.MotionControl.IntegratedStepperMotorsCLI.CageRotator.DevicePrefix}
                    % check physical limits
                    if val > h.vellimit
                        error('Requested acceleration is higher than the physical limit, which is %.2f',h.vellimit);
                    end
                    velpars = h.deviceNET.GetVelocityParams(); % Get existing velocity and acceleration parameters
                    velpars.MaxVelocity = val;
                    h.deviceNET.SetVelocityParams(velpars); % Set velocity and acceleration paraneters via .NET interface
                case Thorlabs.MotionControl.Benchtop.BrushlessMotorCLI.BenchtopBrushlessMotor.DevicePrefix103
                    for km = 1:double(h.deviceInfoNET.NumChannels)
                        % check physical limits
                        if val(km) > h.vellimit(km)
                            error('Requested velocity is higher than the physical limit for Ch%d, which is %.2f',km,h.vellimit(km));
                        end
                        velpars = h.channel{km}.GetVelocityParams(); % Get existing velocity and acceleration parameters
                        velpars.MaxVelocity = val(km);
                        h.channel{km}.SetVelocityParams(velpars); % Set velocity and acceleration paraneters via .NET interface
                    end
            end
        end

        % =================================================================
        function val = get.maxvelocity(h)
            switch(h.prefix)
                case {Thorlabs.MotionControl.KCube.DCServoCLI.KCubeDCServo.DevicePrefix,...
                      Thorlabs.MotionControl.IntegratedStepperMotorsCLI.CageRotator.DevicePrefix}
                    velpars = h.deviceNET.GetVelocityParams(); % Get existing velocity and acceleration parameters
                    val = System.Decimal.ToDouble(velpars.MaxVelocity);
                case Thorlabs.MotionControl.Benchtop.BrushlessMotorCLI.BenchtopBrushlessMotor.DevicePrefix103
                    for km = 1:double(h.deviceInfoNET.NumChannels)
                        velocityparams{km} = h.channel{km}.GetVelocityParams();             %#ok<AGROW> % update velocity parameter
                        val(km) = System.Decimal.ToDouble(velocityparams{km}.MaxVelocity); %#ok<AGROW> % update acceleration parameter
                    end
            end
        end

        % =================================================================
        function set.minvelocity(h, val)
            switch(h.prefix)
                case {Thorlabs.MotionControl.KCube.DCServoCLI.KCubeDCServo.DevicePrefix,...
                      Thorlabs.MotionControl.IntegratedStepperMotorsCLI.CageRotator.DevicePrefix}
                    % check physical limits
                    if val > h.vellimit
                        error('Requested velocity is higher than the physical limit, which is %.2f',h.vellimit);
                    end
                    velpars = h.deviceNET.GetVelocityParams(); % Get existing velocity and acceleration parameters
                    velpars.MinVelocity = val;
                    h.deviceNET.SetVelocityParams(velpars); % Set velocity and acceleration paraneters via .NET interface
                case Thorlabs.MotionControl.Benchtop.BrushlessMotorCLI.BenchtopBrushlessMotor.DevicePrefix103
                    for km = 1:double(h.deviceInfoNET.NumChannels)
                        % check physical limits
                        if val(km) > h.vellimit(km)
                            error('Requested velocity is higher than the physical limit for Ch%d, which is %.2f',km,h.vellimit(km));
                        end
                        velpars = h.channel{km}.GetVelocityParams(); % Get existing velocity and acceleration parameters
                        velpars.MinVelocity = val(km);
                        h.channel{km}.SetVelocityParams(velpars); % Set velocity and acceleration paraneters via .NET interface
                    end
            end
        end

        % =================================================================
        function val = get.minvelocity(h)
            switch(h.prefix)
                case {Thorlabs.MotionControl.KCube.DCServoCLI.KCubeDCServo.DevicePrefix,...
                      Thorlabs.MotionControl.IntegratedStepperMotorsCLI.CageRotator.DevicePrefix}
                    velpars = h.deviceNET.GetVelocityParams(); % Get existing velocity and acceleration parameters
                    val = System.Decimal.ToDouble(velpars.MinVelocity);
                case Thorlabs.MotionControl.Benchtop.BrushlessMotorCLI.BenchtopBrushlessMotor.DevicePrefix103
                    for km = 1:double(h.deviceInfoNET.NumChannels)
                        velocityparams{km} = h.channel{km}.GetVelocityParams();             %#ok<AGROW> % update velocity parameter
                        val(km) = System.Decimal.ToDouble(velocityparams{km}.MinVelocity); %#ok<AGROW> % update acceleration parameter
                    end
            end
        end

        % =================================================================
        function set.position(~, ~)
            error('You cannot set the Position property directly - please use moveto() function or similar!\n');            
        end

        % =================================================================
        function val = get.position(h)
            switch(h.prefix)
                case {Thorlabs.MotionControl.KCube.DCServoCLI.KCubeDCServo.DevicePrefix,...
                      Thorlabs.MotionControl.IntegratedStepperMotorsCLI.CageRotator.DevicePrefix}
                    val = System.Decimal.ToDouble(h.deviceNET.Position);        % Read current device position
                case Thorlabs.MotionControl.Benchtop.BrushlessMotorCLI.BenchtopBrushlessMotor.DevicePrefix103
                    for km = 1:double(h.deviceInfoNET.NumChannels)
                        val(km) = System.Decimal.ToDouble(h.channel{km}.Position); %#ok<AGROW> % Read current device position
                    end
            end
        end

        % =================================================================
        function set.isconnected(h, val)
            if val == 1
                error('You cannot set the IsConnected property to 1 directly - please use connect(''serialnumber'') function!');            
            elseif val == 0 && h.isconnected
                h.disconnect;
            else
                error('Unexpected value, could be only set to 0!');            
            end
        end

        % =================================================================
        function val = get.isconnected(h)
            val = logical(h.deviceNET.IsConnected());
        end

    end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% M E T H O D S  (STATIC) - load DLLs, get a list of devices
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

    methods (Static)

        function serialNumbers = listdevices()  % Read a list of serial number of connected devices
            motor.loaddlls; % Load DLLs
            Thorlabs.MotionControl.DeviceManagerCLI.DeviceManagerCLI.Initialize;  % not really needed
            Thorlabs.MotionControl.DeviceManagerCLI.DeviceManagerCLI.BuildDeviceList;  % Build device list
            serialNumbersNet = Thorlabs.MotionControl.DeviceManagerCLI.DeviceManagerCLI.GetDeviceList; % Get device list
            serialNumbers    = cell(serialNumbersNet.ToArray); % Convert serial numbers to cell array
        end

        function loaddlls() % Load DLLs
            if ~exist(motor.INTEGSTEPCLASSNAME,'class')
                try   % Load in DLLs if not already loaded
                    NET.addAssembly([motor.KINESISPATHDEFAULT,motor.DEVICEMANAGERDLL]);
                    NET.addAssembly([motor.KINESISPATHDEFAULT,motor.GENERICMOTORDLL]);
                    NET.addAssembly([motor.KINESISPATHDEFAULT,motor.DCSERVODLL]); 
                    NET.addAssembly([motor.KINESISPATHDEFAULT,motor.INTEGSTEPDLL]); 
                    NET.addAssembly([motor.KINESISPATHDEFAULT,motor.BRUSHLESSDLL]);                     
                catch % DLLs did not load
                    error('Unable to load .NET assemblies')
                end
            end    
        end 

    end % methods (Static)

end