//@ File (label="Input directory",style="directory") inputdir
//@ File (label="Output directory",style="directory") outputdir
//@ string (label="File type", choices={".czi",".nd2",".ome.tiff", ".tif"}, style="listBox") Type
//@ Boolean (label="Batch mode?") arg

//Put ratio image in the input folder and the mask image (mitochondria) in the "x-Masks" folder.
//Also generate cell outline masks by cellpose and put them in the "x-Masks" folder. 
//The name of the outline masks should be matching the ratio images and ends with -max_CP_masks. Use the renaming function from mac.

list = getFileList(inputdir);

for (i=0; i<list.length; i++) {
    showProgress(i+1, list.length);
    filename = inputdir+File.separator + list[i];
    if(Type == ".ome.tiff" ){
    Fname_temp = File.getNameWithoutExtension(filename);
    Fname = File.getNameWithoutExtension(Fname_temp);   
    }
    else{
     Fname = File.getNameWithoutExtension(filename);   	
    	}
    
    coreFname = substring(Fname, 0, lengthOf(Fname)-6);
    	
    Folder_Mask = inputdir+File.separator+ "x-Masks";
    maskfile = Folder_Mask +File.separator+coreFname + "_mask.tif";
    celloutlinefile = Folder_Mask +File.separator+coreFname + "-max_cp_masks.png";
    
    Folder_Mito = outputdir +File.separator+ "1-Vol-mito";
    File.makeDirectory(Folder_Mito);
    Folder_CellV = outputdir +File.separator+ "1-Vol-Cell";
    File.makeDirectory(Folder_CellV);
    
    
    print("\\Clear");
	roiManager("reset");
	roiManager("Show None");
	run("Clear Results");
	run("Collect Garbage");
	
    print(filename);
    print(list[i]);
   
    
     if (endsWith(filename, Type)) {
        setBatchMode(0);
        roiManager("reset");
        run("Bio-Formats Importer", "open=" + filename + " autoscale color_mode=Default split_channels view=Hyperstack stack_order=XYCZT");
        run("Select None");
        ratio_image=getImageID();
        Stack.getDimensions(width, height, ch, slices, frames);
        imagewidth = width;
        imageheight = height;
        imageZstack = slices;
        
        run("Set Measurements...", "bounding redirect=None decimal=9");
		run("Measure");
		px = width / getResult("Width");
		
		
		run("Bio-Formats Importer", "open=" + maskfile + " autoscale color_mode=Default split_channels view=Hyperstack stack_order=XYCZT");
        run("Select None");
		mask_image=getImageID();
		run("Multiply...", "value=255 stack");
		
		run("Bio-Formats Importer", "open=" + celloutlinefile + " autoscale color_mode=Default split_channels view=Hyperstack stack_order=XYCZT");
        run("Select None");
        cell_outline=getImageID();
        run("glasbey_on_dark");
		run("Set Measurements...", "min redirect=None decimal=9");
		run("Select None");
		run("Measure");
		cellpose_ROIn = getResult("Max", 1);
		run("Clear Results");
		
		
		
		//select cells for cropping
		selectImage(ratio_image);
		run("Z Project...", "projection=[Max Intensity]");
		ratioMAX = getImageID();
		run("Fire");
		run("Brightness/Contrast...");
		setMinAndMax(0, 2);

		roiManager("reset");
		run("Tile");
		RoiBegin = roiManager("count");
		if (RoiBegin > 0) {
			roiManager("delete");
		}
		
		run("Labels...", "color=white font=12 show draw");
		roiManager("Show All with labels");
		selectImage(cell_outline);
		run("Remove Border Labels", "left right top bottom");
		kill_boarder=getImageID();
		run("Label image to ROIs", "rm=[RoiManager[size=51, visible=true]]");		
		
		roiManager("Save", outputdir+File.separator+coreFname+"-CellRoiSet.zip");
		CellRoi = roiManager("count");
		FeretMaxArray = newArray(CellRoi);
		FeretMinArray = newArray(CellRoi);
		CellVolArray = newArray(CellRoi);
		SumMitoVolArray = newArray(CellRoi);
		selectImage(cell_outline);
		run("Duplicate...", "use");
		run("Labels...", "color=white font=18 show draw");
		roiManager("Show All with labels");
		run("Flatten");
		saveAs("Tiff", outputdir+File.separator+"0-"+coreFname+"-cells-marked.tif");
		close();
		
		//cropping the cells
		for (j = 0; j < CellRoi; j++) {
			setBatchMode(arg);
			roiManager("reset");
			roiManager("Open", outputdir+File.separator+coreFname+"-CellRoiSet.zip");
			selectImage(mask_image);
			roiManager("select", j);
			roiManager("rename", j+1);
			nCell = j+1;
			pad_nCell = IJ.pad(nCell, 3);

			selectImage(mask_image);
			run("Select None");
			roiManager("select", j);
			run("Duplicate...", "duplicate");
			run("Clear Outside", "stack");
			cropmitomaskImage = getImageID();
			
			selectImage(ratio_image);
			run("Select None");
			roiManager("select", j);
			run("Duplicate...", "duplicate");
			run("Clear Outside", "stack");
			cropmitoratioImage = getImageID();
			
			
			selectImage(ratio_image);
			run("Clear Results");
			run("Set Scale...", "distance="+ px +" known=1 unit=micron");
			run("Set Measurements...", "feret's redirect=None decimal=9");
			roiManager("Select", j);	
			run("Measure");
			cell_Feret = getValue("Feret");
			FeretMaxArray[j] =cell_Feret;
			cell_minFeret = getValue("MinFeret");
			FeretMinArray[j] =cell_minFeret;
			cellVol = (4/3)*PI*(cell_Feret/2)*(cell_minFeret/2)*3 ;
			CellVolArray[j] =cellVol;
			
			run("Clear Results");
			run("Select None");
			
			selectImage(cell_outline);
			run("Set Scale...", "distance="+ px +" known=1 unit=micron");			
			run("Set Measurements...", "area fit shape feret's redirect=None decimal=9");
			roiManager("Select", j);
			run("Measure");
			selectWindow("Results");
			saveAs("Text", Folder_CellV+ File.separator + coreFname + "-Cell" + pad_nCell+ "-morph.txt");
			close("results");
			
			
							
			setBatchMode(arg);
			
			selectImage(cropmitomaskImage);
			//run("NaN Background", "stack");
			run("3D Manager");
			Ext.Manager3D_Segment(128, 255);
			Ext.Manager3D_AddImage();
			Ext.Manager3D_Count(nb_obj);
			if (nb_obj > 0) {
					selectImage(cropmitoratioImage);
					Ext.Manager3D_Measure();
					Ext.Manager3D_SaveResult("M", Folder_Mito+File.separator + coreFname +"-cell"+pad_nCell +"-3D_measure.csv");
					// loop to sum up InD
					sumVolmito = 0;
					for(a=0;a<nb_obj;a++) {
						Ext.Manager3D_Measure3D(a,"Vol",vol);
						sumVolmito += vol;
						}
					print("\\Clear");
					print("Cell Volume in Cell"+pad_nCell +":"+ cellVol+"\n"+
						"Sum mito Volume in Cell"+pad_nCell +":"+ sumVolmito+"\n"
						+"mito vol ratio in Cell"+pad_nCell +":"+ sumVolmito/cellVol );
					selectWindow("Log");
					saveAs("Text", Folder_CellV+ File.separator + coreFname + "-Cell" + pad_nCell+ "vol.txt");
					print("\\Clear");
					SumMitoVolArray[j]=sumVolmito;
					selectImage(cropmitoratioImage);
					Ext.Manager3D_Quantif();
					Ext.Manager3D_SaveResult("Q", Folder_Mito+File.separator + coreFname +"-cell"+pad_nCell +"-3D_quantif.csv");					
					Ext.Manager3D_CloseResult("Q");
					Ext.Manager3D_CloseResult("M");
					//Ext.Manager3D_Save(outputdir +Fname+ "-Cell" + pad_nCell + Region_name +"-mito-Roi3D.zip");
					print("\\Clear");
					close("*-3Dseg");

					selectImage(cropmitomaskImage);
					close();
					selectImage(cropmitoratioImage);
					close();
	
					Ext.Manager3D_Reset();
					Ext.Manager3D_Close();
					if (isOpen("Exception")){
					close("Exception");
				}
					}
				else {
					print("mito: n/a");
					selectWindow("Log");
					//saveAs("Text", outputdir +File.separator+ Fname + "Cell" + pad_nCell+ Region_name +"mito_quantif.csv");
					SumMitoVolArray[j]=0;
					print("\\Clear");
					close("*-3Dseg");
					
					selectImage(cropmitomaskImage);
					close();
					selectImage(cropmitoratioImage);
					close();
					
					
					Ext.Manager3D_Reset();
					Ext.Manager3D_Close();
					if (isOpen("Exception")){
					close("Exception");
				}
					}
			}
			selectImage(mask_image);
			close();
			selectImage(ratio_image);
			close();
			selectImage(cell_outline);
			close();
			close("*");
			}
			
}
					