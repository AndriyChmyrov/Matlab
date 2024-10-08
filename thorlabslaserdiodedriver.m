classdef thorlabslaserdiodedriver < handle 
    % Matlab class to control Thorlabs Laser Driver of ITC4000 series or CLD1015
    % It is a 'wrapper' to control the devices via .NET DLLs provided by Thorlabs.
    %
    % Instructions:
    % Download the software for Laser Diode Controllers from the Thorlabs website:
    % https://www.thorlabs.de/software_pages/ViewSoftwarePage.cfm?Code=4000_Series
    % Edit DLLPATHDEFAULT below to point to the location of the DLLs
    %
    % Example tested for CLD1015 Compact Laser Diode Driver with TEC:
    % laser = thorlabslaserdiodedriver("USB::4883::32847::M00869857::INSTR"); % Create a laser driver object. Get the resource name from Menu => Information => VISA Resource
    % laser.LdCurrSetpoint              % returns the laser diode current setpoint in constant current CW mode and in constant current QCW mode.
    % laser.LdCurrSetpoint = 0.15;      % sets the laser diode current setpoint in constant current CW mode and in constant current QCW mode 
    % laser.switchTecOutput(1)          % switch the TEC output on
    % laser.switchTecOutput(0)          % switch the TEC output off
    % laser.switchLdOutput(1)           % switch the Laser Driver output on
    % laser.switchLdOutput(0)           % switch the Laser Driver output off
    % laser.switchModulation(1)         % switches the modulation on
    % laser.switchModulation(0)         % switches the modulation off
    % clear laser                       % Clear device object from memory
    %
    %
    % Author: Andriy Chmyrov 
    % Helmholtz Zentrum Muenchen, Deutschland
    % Email: andriy.chmyrov@helmholtz-muenchen.de
    % 
    %
    % Version History:
    % 1.0 29 Nov 2023 - initial implementation targeted on for CLD1015
    
    properties (SetAccess = private)
       % These properties are within Matlab wrapper 
       resourceName;          % specifies the interface of the device that is to be initialized
    end

    properties 
        % Zernike_Order = 4;  % Zernike fit up to order
    end

    properties (Dependent)
        LdCurrSetpoint;       % This parameter specifies the laser diode current setpoint in Amperes
        TecCurrSetpoint;      % This parameter specifies the peltier current in Amperes.
        TecCurrLimit;         % This parameter specifies the peltier current limit value in Amperes.
    end

    properties (Hidden)
       % These are properties within the .NET environment. 
       deviceNET;             % Device object within .NET
       Initialized = false;   % initialization flag
    end

    properties (Constant, Hidden)
        % path to DLL files (edit as appropriate)
        DLLPATHDEFAULT = 'C:\Program Files\IVI Foundation\VISA\VisaCom64\Primary Interop Assemblies\';

        % DLL files to be loaded
        WFSDLL = 'Thorlabs.TL4000_64.dll';
        WFSCLASSNAME = 'Thorlabs.TL4000_64.TL4000';
    end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% M E T H O D S - CONSTRUCTOR/DESCTRUCTOR
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    methods

        % =================================================================
        function h = thorlabslaserdiodedriver(resourceName) % Constructor - Instantiate motor object
            h.loaddlls; % Load DLLs (if not already loaded)
            if ~h.Initialized
                % h.deviceNET = Thorlabs.TL4000_64.TL4000( System.IntPtr(0) );
                if nargin < 1
                    resourceName = "USB::4883::32847::M00869857::INSTR";
                end
                h.deviceNET = Thorlabs.TL4000_64.TL4000( System.String(resourceName), true, false );
                h.Initialized = true;

                str1 = System.Text.StringBuilder();
                str2 = System.Text.StringBuilder();
                retVal = h.deviceNET.revisionQuery(str1,str2);  %#ok<NASGU>
                fprintf('Thorlabs Laser Diode Driver instrument driver version: %s %s\n', str1.ToString, str2.ToString);
            end
        end

        % =================================================================
        function delete(h) % Destructor 
            if ~isempty(h.deviceNET)
                h.Initialized = false;
            end
        end
    end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% M E T H O D S (Sealed) - INTERFACE IMPLEMENTATION
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

    methods (Sealed)

        % =================================================================
        function switchTecOutput(h, TEC_Output)
        % This function switches the TEC output on/off
            [retVal, TEC_Output_now] = h.deviceNET.getTecOutputState(); %#ok<ASGLU>
            if logical(TEC_Output) ~= TEC_Output_now
                h.deviceNET.switchTecOutput(logical(TEC_Output));
            end
        end

        % =================================================================
        function switchLdOutput(h, LD_Output)
        % This function switches the LD output on/off
            [retVal, LD_Output_now] = h.deviceNET.getLdOutputState(); %#ok<ASGLU>
            if logical(LD_Output) ~= LD_Output_now
                h.deviceNET.switchLdOutput(logical(LD_Output));
            end
        end

        % =================================================================
        function switchModulation(h, Modulation_State)
        % This function switches the modulation on/off
            [retVal, Modulation_State_now] = h.deviceNET.getModState(); %#ok<ASGLU>
            if logical(Modulation_State) ~= Modulation_State_now
                h.deviceNET.switchModulation(logical(Modulation_State));
            end
        end

    end % methods (Sealed)

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% M E T H O D S - DEPENDENT, REQUIRE SET/GET
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

    methods

        % =================================================================
        function set.LdCurrSetpoint(h, val)
        % This function sets the laser diode current setpoint in constant current CW mode and in constant current QCW mode
            Laser_Diode_Current_Setpoint = double(val);
            h.deviceNET.setLdCurrSetpoint(Laser_Diode_Current_Setpoint);
        end

        % =================================================================
        function val = get.LdCurrSetpoint(h)
        % This function returns the laser diode current setpoint in constant current CW mode and in constant current QCW mode.
            [RetVal, Laser_Diode_Current_Setpoint] = h.deviceNET.getLdCurrSetpoint(Thorlabs.TL4000_64.TL4000Constants.AttrSetVal); %#ok<ASGLU> 
            val = Laser_Diode_Current_Setpoint;
        end

        % =================================================================
        function set.TecCurrSetpoint(h, val)
        % This function sets the peltier current in current source operating mode.
            TEC_Current_Setpoint = double(val);
            h.deviceNET.setTecCurrSetpoint(TEC_Current_Setpoint);
        end

        % =================================================================
        function val = get.TecCurrSetpoint(h)
        % This function returns the peltier current setpoint in current  source mode.
            [RetVal, TEC_Current_Setpoint] = h.deviceNET.getTecCurrSetpoint(Thorlabs.TL4000_64.TL4000Constants.AttrSetVal); %#ok<ASGLU> 
            val = TEC_Current_Setpoint;
        end

        % =================================================================
        function set.TecCurrLimit(h, val)
        % This function sets the peltier current limit.
            TEC_Current_Limit = double(val);
            h.deviceNET.setTecCurrLimit(TEC_Current_Limit);
        end

        % =================================================================
        function val = get.TecCurrLimit(h)
        % This function returns the peltier current limit settings.
            [RetVal, TEC_Current_Limit] = h.deviceNET.getTecCurrLimit(Thorlabs.TL4000_64.TL4000Constants.AttrSetVal); %#ok<ASGLU> 
            val = TEC_Current_Limit;
        end

    end % methods (dependent)

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% M E T H O D S  (STATIC) - load DLLs, get a list of devices
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

    methods (Static)

        function loaddlls() % Load DLLs
            if ~exist(thorlabslaserdiodedriver.WFSCLASSNAME,'class')
                try   % Load in DLLs if not already loaded
                    NET.addAssembly([thorlabslaserdiodedriver.DLLPATHDEFAULT,thorlabslaserdiodedriver.WFSDLL]);
                catch % DLLs did not load
                    error('Unable to load .NET assembly %s from the folder %s',thorlabslaserdiodedriver.WFSDLL,thorlabslaserdiodedriver.DLLPATHDEFAULT)
                end
            end    
        end 

    end % methods (Static)

end