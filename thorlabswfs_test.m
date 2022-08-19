wfs = thorlabswfs;      % Create a wavefront sensor object. Shows a list of avialable devices
wfs.connect             % Connect the first (default) devce. Alternatively prove a parameter, either DeviceID: wfs.connect(1025) or full Resource Name: wfs.connect('USB::0x1313::0x0000::1025')
wfs.configureDevice     % configures the sensor for max resolution (1936x1216 for WFS30-7AR)
wfs.configureDevice(2)  % configures the sensor for pre-defined resolution set number 2 = CAM_RES_WFS30_1024. See code for possible values
wfs.setReferencePlane   % set WFS reference plane to internal
wfs.adjustImageBrightness % call autoadjustment routine to set Camera Exposure and Gain
wfs.Exposure_Time       % display camera Exposure Time
wfs.Master_Gain         % display camera Master Gain
wfs.Black_Level_Offset  % Set/get the black offset value of the WFS camera. A higher black level will increase the intensity level of a dark camera image.
wfs.Cancel_Wavefront_Tilt = 0 % Flag to cancel average wavefront tip and tilt during calculations 
wfs.Dynamic_Noise_Cut = 1;    % Flag to use dynamic noise cut features during calculations 
wfs.setAveraging(10);   % Sets number of images for averaging to 10
wfs.Pupil = [-0.5,-2.0,1.1,1.6] % set the Beam Pupil position [-0.5;-2.0] in mm and Beam Pupil Size [1.1;1.6] in mm
wfs.Beam_Centroid       % get 1x4 vector [ctrX, ctrY, diaX, diaY] with Beam Centroid position [X, Y] in mm and Beam diameter [X, Y] in mm
wfs.Pupil = wfs.Beam_Centroid % update pupil position and size with values of calculated beam centroid 
img = wfs.Spotfield_Image; % returns a copy of the spotfield image.
figure; imagesc(rot90(img,-1)); axis image; colormap gray % display the spotfield image in a figure
wfs.Zernike_Order = 3;  % set number of Zerkine orders. Default number is 4
wfs.Zernike             % Outputs a structure with a vector of the Zernike coefficients up to the desired number of Zernike modes, a vector summarizing these coefficients to rms amplitudes for each Zernike order and RoC (radius of curvature) in mm for a spherical wavefront.
wfs.Wavefront           % Outputs a structure with Min, Max, Diff, Mean, RMS, Weighted_RMS parameters of the wavefront based on the spot deviations
wfs.FourierOptometric   % Outputs a structure with the Fourier and Optometric notations from the Zernike coefficients calculated in function WFS_ZernikeLsf.
wfs.disconnect          % Disconnect sensor (not strictly necessary - device is disconnected automatically using destructor)
clear wfs               % Clear device object from memory
