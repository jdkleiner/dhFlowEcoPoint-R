library(quantreg);
library(ggplot2);
library(ggrepel);
library(ggpmisc);
library(grid);
library(httr);
library(data.table);
library(scales);

#Load elf skip function               
source(paste(fxn_locations,"elf_skip.R", sep = ""));

elf_quantreg <- function(inputs, data, x_metric_code, y_metric_code, ws_ftype_code, Feature.Name_code, Hydroid_code, search_code, token, nhdplus_flowmetric_value, startdate, enddate){
    
  #Load inputs
  x_metric <- x_metric_code
  y_metric <- y_metric_code
  Feature.Name <- Feature.Name_code
  Hydroid <- Hydroid_code
  ws_ftype <- ws_ftype_code
  pct_chg <- inputs$pct_chg 
  save_directory <- inputs$save_directory 
  target_hydrocode <- inputs$target_hydrocode
  quantile <- inputs$quantile  
  xaxis_thresh <- inputs$xaxis_thresh
  send_to_rest <- inputs$send_to_rest
  offset <- inputs$offset
  analysis_timespan <- inputs$analysis_timespan
  station_agg <- inputs$station_agg
  site <- inputs$site
  sampres <- inputs$sampres
  ghi <- inputs$ghi
  dataset_tag <- inputs$dataset_tag

  full_dataset <- data
  
  #Convert ghi input from sqmi to sqkm, and remove datapoints greater than the ghi DA threashold
  data<-data[!(data$drainage_area > (ghi * 2.58999)),]
  subset_n <- length(data$metric_value)
  # do not convert ghi here since we want to store breakpoint as sqmi not sqkm
  stat_quantreg_bkpt <- ghi

  #If statement needed in case there are fewer than 4 datapoints to the left of x-axis inflection point, or if there are more than 3 points but all have the same attribute_value
  duplicates <- unique(data$attribute_value, incomparables = FALSE)
  if(nrow(data) && length(duplicates) > 3) {  
          
          up90 <- rq(metric_value ~ log(attribute_value),data = data, tau = quantile) #calculate the quantile regression
          newy <- c(log(data$attribute_value)*coef(up90)[2]+coef(up90)[1])            #find the upper quantile values of y for each value of DA based on the quantile regression
          upper.quant <- subset(data, data$metric_value > newy)                        #create a subset of the data that only includes the stations with NT values higher than the y values just calculated
          
print(paste("Upper quantile has ", nrow(upper.quant), "values"));
          #If statement needed in case there ae fewer than 4 datapoints in upper quantile of data set
          if (nrow(upper.quant) > 3) {

            regupper <- lm(metric_value ~ log(attribute_value),data = upper.quant)  
            ru <- summary(regupper)                                                  #regression for upper quantile
            #print(ru)
            #print(ru$coefficients)
            #print(nrow(ru$coefficients))
            
            #If statement needed in case slope is "NA"
            if (nrow(ru$coefficients) > 1) {
            
            ruint <- round(ru$coefficients[1,1], digits = 6)                         #intercept 
            ruslope <- round(ru$coefficients[2,1], digits = 6)                       #slope of regression
            rurs <- round(ru$r.squared, digits = 6)                                  #r squared of upper quantile
            rursadj <- round(ru$adj.r.squared, digits = 6)                           #adjusted r squared of upper quantile
            rup <- round(ru$coefficients[2,4], digits = 6)                           #p-value of upper quantile
            rucor <-round(cor.test(log(upper.quant$attribute_value),upper.quant$metric_value)$estimate, digits = 6) #correlation coefficient of upper quantile
            rucount <- length(upper.quant$metric_value)
            regfull <- lm(metric_value ~ log(attribute_value),data = data)            
            rf <- summary(regfull)                                                   #regression for full dataset
            rfint <- round(rf$coefficients[1,2], digits = 6)                         #intercept 
            rfslope <- round(rf$coefficients[2,1], digits = 6)                       #slope of regression
            rfrs <- round(rf$r.squared, digits = 6)                                  #r squared of full dataset linear regression
            rfp <- round(rf$coefficients[2,4], digits = 6)                           #p-value of full dataset
            rfcor <- round(cor.test(log(data$attribute_value),data$metric_value)$estimate, digits = 6) #correlation coefficient of full dataset
            rfcount <- length(data$metric_value) 
            
            #Set yaxis threshold = to maximum biometric value in database 
            yaxis_thresh <- paste(site,"/femetric-ymax/",y_metric, sep="")
            yaxis_thresh <- read.csv(yaxis_thresh , header = TRUE, sep = ",")
            yaxis_thresh <- yaxis_thresh$metric_value
            print (paste("Setting ymax = ", yaxis_thresh));

            #retreive metric varids and varnames
            metric_definitions <- paste(site,"/?q=/fe_metric_export",sep="");
            metric_table <- read.table(metric_definitions,header = TRUE, sep = ",")
            
            biometric_row <- which(metric_table$varkey == y_metric)
            biomeric_name <- metric_table[biometric_row,]
            biometric_title <- biomeric_name$varname                #needed for human-readable plot titles
            
            flow_row <- which(metric_table$varkey == x_metric)
            flow_name <- metric_table[flow_row,]
            flow_title <- flow_name$varname                         #needed for human-readable plot titles

            admincode <-paste(Hydroid,"_fe_quantreg",sep="");       
            
            
        # stash the regression statistics using REST  
           if (send_to_rest == 'YES') {
   
             qd <- list(
               featureid = Hydroid,
               admincode = admincode,
               name = paste( "Quantile Regression, ", y_metric, ' = f( ', x_metric, ' ), upper ',quantile * 100, '%', sep=''),
               ftype = 'fe_quantreg',
               site = site,
               x = x_metric,
               y = y_metric,
               stats = list(
                 stat_quantreg_m = ruslope,
                 stat_quantreg_b = ruint,
                 stat_quantreg_n = rucount,
                 stat_quantreg_p = rup,
                 stat_quantreg_rsq = rurs,
                 stat_quantreg_adj_rsq = rursadj,
                 stat_quantreg_qu = quantile,
                 stat_quantreg_x = x_metric,
                 stat_quantreg_y = y_metric,
                 station_agg =station_agg,
                 sampres = sampres,
                 stat_quantreg_bkpt = stat_quantreg_bkpt,
                 stat_quantreg_glo = 0,
                 stat_quantreg_ghi = ghi,
                 analysis_timespan = analysis_timespan
               )
             );
             print("Storing quantile regression.");
             adminid <- elf_store_data(qd, token, inputs, adminid)
           } else {
             adminid <- paste(target_hydrocode,"_fe_quantreg",sep="") #Plot images are stored using watershed hydrocode when NOT performing REST 
           }

            #Display only 3 significant digits on plots
            plot_ruslope <- signif(ruslope, digits = 3)
            plot_ruint <- signif(ruint, digits = 3)
            plot_rurs <- signif(rurs, digits = 3)
            plot_rursadj <- signif(rursadj, digits = 3)
            plot_rup <- signif(rup, digits = 3)

            #ADD ANALYSIS POINT TO PLOT
            analysis_point_x <- nhdplus_flowmetric_value
            #analysis_point_y <- (ruslope*analysis_point_x)+ruint #linear 
            analysis_point_y <- (ruslope*log(analysis_point_x))+ruint #natural log
            analysis_point <- data.frame(analysis_point_x,analysis_point_y)
            #print(analysis_point)
      
            #ADD DASH LINES TO PLOT
            zero_x <- data.frame(0,analysis_point$analysis_point_y)
            zero_y <- data.frame(analysis_point$analysis_point_x,0)
            names(zero_x) <- c('analysis_point_x','analysis_point_y')
            names(zero_y) <- c('analysis_point_x','analysis_point_y')
            analysis_point_line_x <- rbind(analysis_point, zero_x)
            analysis_point_line_y <- rbind(analysis_point, zero_y)
            print(analysis_point_line_x)
            print(analysis_point_line_y)
            
            #Plot titles
            plot_title <- paste(Feature.Name," (",sampres," grouping)\n",
                                startdate," to ",
                                enddate,"\n\nQuantile Regression: (breakpoint at DA = ", ghi, 
                                ' sqmi, ', round((ghi  * 2.58999),digits=0),' sqkm)',
                                sep="");
            xaxis_title <- paste(flow_title,"\n","\n","m: ",plot_ruslope,"    b: ",plot_ruint,"    r^2: ",plot_rurs,"    adj r^2: ",plot_rursadj,"    p: ",plot_rup,"\n","    Upper ",((1 - quantile)*100),"% n: ",rucount,"    Data Subset n: ",subset_n,sep="");
            yaxis_title <- paste(biometric_title);
            EDAS_upper_legend <- paste("Data Subset (Upper ",((1 - quantile)*100),"%)",sep="");
            Reg_upper_legend <- paste("Regression (Upper ",((1 - quantile)*100),"%)",sep="");       
            Quantile_Legend <- paste(quantile," Quantile (Data Subset)",sep=""); 
            EDAS_lower_legend <- paste("Data Subset (Lower ",(100-((1 - quantile)*100)),"%)",sep="");
            plot_annotation <- paste("Max Limit to Ecology: ", signif(analysis_point_y, digits = 3),"\n",flow_title,": ",analysis_point_x,sep="")
            
            #-OUTPUT------------------------------------------------------------------------------------------            
            output_x <- c(0,1)
            output_y <- c(0,1)
            output_frame <- data.frame(output_x,output_y)
            
            output <- ggplot(output_frame , aes(x=output_x,y=output_y)) + 
              annotate("text", x=0.5, y=0.5, label= plot_annotation,colour = "red",size =10)+
              theme(axis.title.x=element_blank(),
                    axis.text.x=element_blank(),
                    axis.ticks.x=element_blank(),
                    axis.title.y=element_blank(),
                    axis.text.y=element_blank(),
                    axis.ticks.y=element_blank())
            
            
            # END plotting function
            filename <- paste("279034-analysis-point-elf-output.png", sep="")
            ggsave(file=filename, path = save_directory, width=8, height=5)
            #-------------------------------------------------------------------------------------------
            
print (paste("Plotting ELF"));
            # START - plotting function
            plt <- ggplot(data, aes(x=attribute_value,y=metric_value)) + ylim(0,yaxis_thresh) + 
              geom_point(data = full_dataset,aes(colour="aliceblue")) +
              geom_point(data = data,aes(colour="blue")) + 
              stat_smooth(method = "lm",fullrange=FALSE,level = .95, data = upper.quant, aes(x=attribute_value,y=metric_value,color = "red")) +
              geom_point(data = upper.quant, aes(x=attribute_value,y=metric_value,color = "black")) + 
              geom_quantile(data = data, quantiles= quantile,show.legend = TRUE,aes(color="red")) + 
              geom_smooth(data = data, method="lm",formula=y ~ x,show.legend = TRUE, aes(colour="yellow"),se=FALSE) + 
              geom_smooth(data = upper.quant, formula = y ~ x, method = "lm", show.legend = TRUE, aes(x=attribute_value,y=metric_value,color = "green"),se=FALSE) + 
             
              geom_point(data = analysis_point, aes(x=analysis_point_x,y=analysis_point_y,color = "yellow2"),size=5,shape=17) + 
              geom_line(data = analysis_point_line_x, aes(x=analysis_point_x, y=analysis_point_y, color = "yellow3"),size=1,linetype=2, show.legend = FALSE) +
              geom_line(data = analysis_point_line_y, aes(x=analysis_point_x, y=analysis_point_y, color = "yellow4"),size=1,linetype=2, show.legend = FALSE) +
              
              ggtitle(plot_title) + 
              theme(
                plot.title = element_text(size = 12, face = "bold"),axis.text = element_text(colour = "blue")
              ) +
              labs(x=xaxis_title,y=yaxis_title) + 
              scale_x_log10(
                limits = c(0.001,15000),
                breaks = trans_breaks("log10", function(x) {10^x}),
                labels = trans_format("log10", math_format(10^.x))
              ) + 
              annotation_logticks(sides = "b")+
              theme(legend.key=element_rect(fill='white')) +
              #Add legend
              scale_color_manual(
                "Legend",
                values=c("gray66","forestgreen","blue","orange","black","purple","red","firebrick1","firebrick1"),
                labels=c("Full Dataset",EDAS_upper_legend,EDAS_lower_legend,Reg_upper_legend,Quantile_Legend,"Regression (Data Subset)","Analysis Point","","")
              ) + 
              guides(
                colour = guide_legend(
                  override.aes = list(
                    linetype=c(0,0,0,1,1,1,0,0,0), 
                    shape=c(16,16,16,NA,NA,NA,17,NA,NA),
                    fill=NA
                  ),
                  label.position = "right"
                )
              ); 
            
            # END plotting function
              filename <- paste("279034-analysis-point-elf.png", sep="")
              ggsave(file=filename, path = save_directory, width=8, height=6)

              
      print (paste("Plotting Barplot"));
      print (paste("ELF Slope: ",ruslope,sep="")); 
      print (paste("ELF Y-Intercept: ",ruint,sep="")); 
      if (ruslope >= 0){
        if (ruint >= 0){
          
          #slope barplot  
          pct_inputs<- list(ruslope = ruslope, 
                            ruint = ruint,
                            biometric_title = biometric_title, 
                            flow_title = flow_title,
                            Feature.Name = Feature.Name,
                            pct_chg = pct_chg,
                            sampres = sampres,
                            startdate = startdate,
                            enddate = enddate,
                            analysis_point = analysis_point,
                            save_directory = save_directory)
          elf_pct_chg (pct_inputs)
          

          filename <- paste("279034-analysis-point-barplot.png", sep="")
          ggsave(file=filename, path = save_directory, width=8, height=5)
          
        } else {
          print(paste("... Skipping (Y-Intercept is negative, not generating barplot for ", search_code,")", sep=''));
          skipper <- paste("Error:\n\n (Y-Intercept is negative, not generating barplot for \n", search_code,")", sep='')
          elf_skip (save_directory,skipper)
        }  
        
      } else {
        print(paste("... Skipping (Slope is negative, not generating barplot for ", search_code,")", sep=''));
        skipper <- paste("Error:\n\n (Slope is negative, not generating barplot for \n", search_code,")", sep='')
        elf_skip (save_directory,skipper)
      } 
            
            } else {
              print(paste("... Skipping slope is 'NA' for ", search_code,")", sep=''));
              skipper <- paste("Error:\n\n (Slope is 'NA' for \n", search_code,")", sep='')
              elf_skip (save_directory,skipper)
            }   
      
          } else {
              print(paste("... Skipping (fewer than 4 datapoints in upper quantile of ", search_code,")", sep=''));
              skipper <- paste("Error:\n\n (fewer than 4 datapoints in upper quantile of \n", search_code,")", sep='')
              elf_skip (save_directory,skipper)
          }   
                   
        } else {
          print(paste("... Skipping (fewer than 4 datapoints to the left of x-axis inflection point in ", search_code,")", sep=''));
          skipper <- paste("Error:\n\n (fewer than 4 datapoints to the left of x-axis inflection point in \n", search_code,")", sep='')
          elf_skip (save_directory,skipper)
        }   
        
} #close function
