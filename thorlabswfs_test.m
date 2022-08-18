thorlabswfs.loaddlls;
wfs = thorlabswfs;
wfs.connect;
wfs.configureDevice(0);
wfs.setReferencePlane;
wfs.adjustImageBrightness;
wfs.Pupil = [-0.1,0.3,3.3,3.3];
wfs.Pupil = wfs.Beam_Centroid;
img = wfs.Spotfield_Image;
figure; imagesc(rot90(img,-1)); axis image; colormap gray
wfs.Zernike_Order = 3;
wfs.Zernike
wfs.RoC_mm
wfs.Wavefront
wfs.disconnect;
clear wfs