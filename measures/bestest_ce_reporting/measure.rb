# see the URL below for information on how to write OpenStudio measures
# http://nrel.github.io/OpenStudio-user-documentation/reference/measure_writing_guide/

require 'erb'

#start the measure
class BESTESTCEReporting < OpenStudio::Ruleset::ReportingUserScript

  # human readable name
  def name
    return "BESTEST CE Reporting"
  end
  # human readable description
  def description
    return "This doesn't generate a user HTML file with any meaningful content. It is here to create runner.RegisterValue objects that will be post processed downstream."
  end
  # human readable description of modeling approach
  def modeler_description
    return "The CSV project for the analysis will be downloaded from the server and then a script will run to pull data into Local Excel File."
  end
  # define the arguments that the user will input
  def arguments()
    args = OpenStudio::Ruleset::OSArgumentVector.new

    # this measure does not require any user arguments, return an empty list

    return args
  end 
  
  # return a vector of IdfObject's to request EnergyPlus objects needed by the run method
  def energyPlusOutputRequests(runner, user_arguments)
    super(runner, user_arguments)
    
    result = OpenStudio::IdfObjectVector.new
    
    # use the built-in error checking 
    if !runner.validateUserArguments(arguments(), user_arguments)
      return result
    end
    
    return result
  end
  
  # define what happens when the measure is run
  def run(runner, user_arguments)
    super(runner, user_arguments)

    # use the built-in error checking 
    if !runner.validateUserArguments(arguments(), user_arguments)
      return false
    end

    # get the last model and sql file
    model = runner.lastOpenStudioModel
    if model.empty?
      runner.registerError("Cannot find last model.")
      return false
    end
    model = model.get

    sqlFile = runner.lastEnergyPlusSqlFile
    if sqlFile.empty?
      runner.registerError("Cannot find last sql file.")
      return false
    end
    sqlFile = sqlFile.get
    model.setSqlFile(sqlFile)

    # put data into the local variable 'output', all local variables are available for erb to use when configuring the input html file

    output =  "Measure Name = " << name << "<br>"
    output << "Building Name = " << model.getBuilding.name.get << "<br>"                       # optional variable
    output << "Floor Area = " << model.getBuilding.floorArea.to_s << "<br>"                   # double variable
    output << "Floor to Floor Height = " << model.getBuilding.nominalFloortoFloorHeight.to_s << " (m)<br>" # double variable
    output << "Net Site Energy = " << sqlFile.netSiteEnergy.to_s << " (GJ)<br>" # double variable

    web_asset_path = OpenStudio.getSharedResourcesPath() / OpenStudio::Path.new("web_assets")

    # read in template
    html_in_path = "#{File.dirname(__FILE__)}/resources/report.html.in"
    if File.exist?(html_in_path)
        html_in_path = html_in_path
    else
        html_in_path = "#{File.dirname(__FILE__)}/report.html.in"
    end
    html_in = ""
    File.open(html_in_path, 'r') do |file|
      html_in = file.read
    end

    # get the weather file run period (as opposed to design day run period)
    ann_env_pd = nil
    sqlFile.availableEnvPeriods.each do |env_pd|
      env_type = sqlFile.environmentType(env_pd)
      if env_type.is_initialized
        if env_type.get == OpenStudio::EnvironmentType.new("WeatherRunPeriod")
          ann_env_pd = env_pd
          break
        end
      end
    end

    # only try to get the annual timeseries if an annual simulation was run
    if ann_env_pd

      # get desired variable
      key_value =  "Environment"
      time_step = "Hourly" # "Zone Timestep", "Hourly", "HVAC System Timestep"
      variable_name = "Site Outdoor Air Drybulb Temperature"
      output_timeseries = sqlFile.timeSeries(ann_env_pd, time_step, variable_name, key_value) # key value would go at the end if we used it.
      
      if output_timeseries.empty?
        runner.registerWarning("Timeseries not found.")
      else
        runner.registerInfo("Found timeseries.")
      end
    else
      runner.registerWarning("No annual environment period found.")
    end
    
    # configure template with variable values
    renderer = ERB.new(html_in)
    html_out = renderer.result(binding)
    
    # write html file
    html_out_path = "./report.html"
    File.open(html_out_path, 'w') do |file|
      file << html_out
      # make sure data is written to the disk one way or the other
      begin
        file.fsync
      rescue
        file.flush
      end
    end

    # this is in CE and Envelope, move to shared resource
    def process_output_timeseries (sqlFile, runner, ann_env_pd, time_step, variable_name, key_value, days_skip_start = 0, days_skip_end = 0)

      output_timeseries = sqlFile.timeSeries(ann_env_pd, time_step, variable_name, key_value)
      if output_timeseries.empty?
        runner.registerWarning("Timeseries not found for #{variable_name}.")
        return false
      else
        runner.registerInfo("Found timeseries for #{variable_name}.")
        output_values = output_timeseries.get.values
        output_times = output_timeseries.get.dateTimes
        array = []
        sum = 0.0
        min = nil
        min_date_time = nil
        max = nil
        max_date_time = nil

        start_value = 0 + days_skip_start * 24
        end_value = output_values.size - 1 - days_skip_end * 24

        for i in start_value..end_value

          # using this to get average
          array << output_values[i]
          sum += output_values[i]

          # code for min and max
          if min.nil? || output_values[i] < min
            min = output_values[i]
            min_date_time = output_times[i]
          end
          if max.nil? || output_values[i] > max
            max = output_values[i]
            max_date_time = output_times[i]
          end

        end
        return {:array => array, :sum => sum, :avg => sum/array.size.to_f, :min => min, :max => max, :min_date_time => min_date_time, :max_date_time => max_date_time}
      end

    end

    def date_time_parse(date_time)

      array = []

      month = date_time.date.monthOfYear.value
      day_of_month = date_time.date.dayOfMonth.to_s
      hour = date_time.time.hours

      # map month integer to short name
      case month
        when 1
          month = "Jan"
        when 2
          month = "Feb"
        when 3
          month = "Mar"
        when 4
          month = "Apr"
        when 5
          month = "May"
        when 6
          month = "Jun"
        when 7
          month = "Jul"
        when 8
          month = "Aug"
        when 9
          month = "Sep"
        when 10
          month = "Oct"
        when 11
          month = "Nov"
        when 12
          month = "Dec"
      end

      array << "#{"%02d" % day_of_month}-#{month}"
      array << hour

      return array

    end

    # date format should be dd-MMM. Hour is integer
    # note: This is also used in the bestest_populate_report.rb for envelope
    def self.return_date_time_from_8760_index(index)

      date_string = nil
      dd = nil
      mmm = nil
      hour = nil

      # assuming non leap year
      month_hash = {}
      month_hash['JAN'] = 31
      month_hash['FEB'] = 28
      month_hash['MAR'] = 31
      month_hash['APR'] = 30
      month_hash['MAY'] = 31
      month_hash['JUN'] = 30
      month_hash['JUL'] = 31
      month_hash['AUG'] = 31
      month_hash['SEP'] = 30
      month_hash['OCT'] = 31
      month_hash['NOV'] = 30
      month_hash['DEC'] = 31

      raw_date = (index/24.0).floor
      counter = 0
      month_hash.each do |k,v|
        if raw_date - counter <= v
          # found month
          mmm = k
          dd = 1 + raw_date - counter
          date_string = "#{"%02d" % dd}-#{mmm}"
          hour = (index % 24)
          return [date_string,hour]
        else
          counter = counter + v
        end
      end
      return nil # shouldn't hit this
    end

    # add runner.registerValues for bestest reporting 5-3A
    if model.getBuilding.name.to_s.include? "CE1" or model.getBuilding.name.to_s.include? "CE2"

      # get clg_energy_consumption_total
      key_value =  "BESTEST CE AIR LOOP"
      variable_name = "Air System Electric Energy"
      timeseries_hash = process_output_timeseries(sqlFile, runner, ann_env_pd, 'Hourly', variable_name, key_value,31,306)
      total_cooling_energy_consumption_j = timeseries_hash
      value_kwh = OpenStudio.convert(timeseries_hash[:sum],'J','kWh').get
      runner.registerValue('clg_energy_consumption_total',value_kwh)
      # get clg_energy_consumption_compressor
      variable_name = "Air System DX Cooling Coil Electric Energy"
      timeseries_hash = process_output_timeseries(sqlFile, runner, ann_env_pd, 'Hourly', variable_name, key_value,31,306)
      value_kwh = OpenStudio.convert(timeseries_hash[:sum],'J','kWh').get
      runner.registerValue('clg_energy_consumption_compressor',value_kwh)
      # get clg_energy_consumption_supply_fan
      variable_name = "Air System Fan Electric Energy"
      timeseries_hash = process_output_timeseries(sqlFile, runner, ann_env_pd, 'Hourly', variable_name, key_value,31,306)
      value_kwh = OpenStudio.convert(timeseries_hash[:sum],'J','kWh').get
      runner.registerValue('clg_energy_consumption_supply_fan',value_kwh)
      # todo - can I get d directly or does d = a - b - c
      runner.registerValue('clg_energy_consumption_condenser_fan','tbd')

      # get evaporator_coil_load_total
      key_value =  "COIL COOLING DX SINGLE SPEED 1"
        variable_name = "Cooling Coil Total Cooling Rate"
      timeseries_hash = process_output_timeseries(sqlFile, runner, ann_env_pd, 'Hourly', variable_name, key_value,31,306)
      value_kwh = OpenStudio.convert(timeseries_hash[:sum],'Wh','kWh').get
      runner.registerValue('evaporator_coil_load_total',value_kwh)
      # get evaporator_coil_load_sensible
      variable_name = "Cooling Coil Sensible Cooling Rate"
      timeseries_hash = process_output_timeseries(sqlFile, runner, ann_env_pd, 'Hourly', variable_name, key_value,31,306)
      value_kwh = OpenStudio.convert(timeseries_hash[:sum],'Wh','kWh').get
      runner.registerValue('evaporator_coil_load_sensible',value_kwh)
      # get evaporator_coil_load_latent
      variable_name = "Cooling Coil Latent Cooling Rate"
      timeseries_hash = process_output_timeseries(sqlFile, runner, ann_env_pd, 'Hourly', variable_name, key_value,31,306)
      value_kwh = OpenStudio.convert(timeseries_hash[:sum],'Wh','kWh').get
      runner.registerValue('evaporator_coil_load_latent',value_kwh)

      # get zone_load_total
      key_value =  "AIR LOOP HVAC UNITARY SYSTEM 1"
      variable_name = "Unitary System Total Cooling Rate"
      timeseries_hash = process_output_timeseries(sqlFile, runner, ann_env_pd, 'Hourly', variable_name, key_value,31,306)
      net_refrigeration_effect_w = timeseries_hash
      value_kwh = OpenStudio.convert(timeseries_hash[:sum],'Wh','kWh').get
      runner.registerValue('zone_load_total',value_kwh)
      # get zone_load_sensible
      variable_name = "Unitary System Sensible Cooling Rate"
      timeseries_hash = process_output_timeseries(sqlFile, runner, ann_env_pd, 'Hourly', variable_name, key_value,31,306)
      value_kwh = OpenStudio.convert(timeseries_hash[:sum],'Wh','kWh').get
      runner.registerValue('zone_load_sensible',value_kwh)
      # get zone_load_latent
      variable_name = "Unitary System Latent Cooling Rate"
      timeseries_hash = process_output_timeseries(sqlFile, runner, ann_env_pd, 'Hourly', variable_name, key_value,31,306)
      value_kwh = OpenStudio.convert(timeseries_hash[:sum],'Wh','kWh').get
      runner.registerValue('zone_load_latent',value_kwh)

      # get feb_cop
      mean_cop = net_refrigeration_effect_w[:avg] / (total_cooling_energy_consumption_j[:avg]/3600.0) # W = J/s
      runner.registerValue('feb_mean_cop',mean_cop)
      cop_array = []
      total_cooling_energy_consumption_j[:array].size.times.each do |i|
        cop_array << net_refrigeration_effect_w[:array][i]/(total_cooling_energy_consumption_j[:array][i]/3600.0) # W = J/s
      end
      runner.registerValue('feb_max_cop',cop_array.max)
      runner.registerValue('feb_min_cop',cop_array.min)
      # get feb_idb
      key_value =  "ZONE ONE"
      variable_name = "Zone Mean Air Temperature"
      timeseries_hash = process_output_timeseries(sqlFile, runner, ann_env_pd, 'Hourly', variable_name, key_value,31,306)
      runner.registerValue('feb_mean_idb',timeseries_hash[:avg])
      runner.registerValue('feb_max_idb',timeseries_hash[:max])
      runner.registerValue('feb_min_idb',timeseries_hash[:min])
      # get feb_humidity_ratio
      key_value =  "ZONE ONE"
      variable_name = "Zone Mean Air Humidity Ratio"
      timeseries_hash = process_output_timeseries(sqlFile, runner, ann_env_pd, 'Hourly', variable_name, key_value,31,306)
      runner.registerValue('feb_mean_humidity_ratio',timeseries_hash[:avg])
      runner.registerValue('feb_max_humidity_ratio',timeseries_hash[:max])
      runner.registerValue('feb_min_humidity_ratio',timeseries_hash[:min])

    else

      # Annual Sums and Means Table

      # get clg_energy_consumption_total
      key_value =  "BESTEST CE AIR LOOP"
      variable_name = "Air System Electric Energy"
      timeseries_hash = process_output_timeseries(sqlFile, runner, ann_env_pd, 'Hourly', variable_name, key_value)
      value_kwh = OpenStudio.convert(timeseries_hash[:sum],'J','kWh').get
      runner.registerValue('ann_sum_clg_energy_consumption_total',value_kwh)
      # get clg_energy_consumption_compressor (this includes the compressor fan)
      variable_name = "Air System DX Cooling Coil Electric Energy"
      timeseries_hash = process_output_timeseries(sqlFile, runner, ann_env_pd, 'Hourly', variable_name, key_value)
      value_kwh = OpenStudio.convert(timeseries_hash[:sum],'J','kWh').get
      # store avg value for cop2
      compressor_and_outdoor_fan = value_kwh
      runner.registerValue('ann_sum_clg_energy_consumption_compressor',value_kwh)
      # indoor fan
      variable_name = "Air System Fan Electric Energy"
      timeseries_hash = process_output_timeseries(sqlFile, runner, ann_env_pd, 'Hourly', variable_name, key_value)
      value_kwh = OpenStudio.convert(timeseries_hash[:sum],'J','kWh').get
      runner.registerValue('ann_sum_clg_energy_consumption_supply_fan',value_kwh)
      # get clg_energy_consumption_supply_fan  (can't calculate this)
      runner.registerValue('ann_sum_clg_energy_consumption_condenser_fan','tbd')
      # get evaporator_coil_load_total
      key_value =  "COIL COOLING DX SINGLE SPEED 1"
      variable_name = "Cooling Coil Total Cooling Rate"
      timeseries_hash = process_output_timeseries(sqlFile, runner, ann_env_pd, 'Hourly', variable_name, key_value)
      value_kwh = OpenStudio.convert(timeseries_hash[:sum],'Wh','kWh').get
      # store avg value for cop2
      evaporator_coil_load = value_kwh
      runner.registerValue('ann_sum_evap_coil_load_total',value_kwh)
      # get evaporator_coil_load_sensible
      variable_name = "Cooling Coil Sensible Cooling Rate"
      timeseries_hash = process_output_timeseries(sqlFile, runner, ann_env_pd, 'Hourly', variable_name, key_value)
      value_kwh = OpenStudio.convert(timeseries_hash[:sum],'Wh','kWh').get
      runner.registerValue('ann_sum_evap_coil_load_sensible',value_kwh)
      # get evaporator_coil_load_latent
      variable_name = "Cooling Coil Latent Cooling Rate"
      timeseries_hash = process_output_timeseries(sqlFile, runner, ann_env_pd, 'Hourly', variable_name, key_value)
      value_kwh = OpenStudio.convert(timeseries_hash[:sum],'Wh','kWh').get
      runner.registerValue('ann_sum_evap_coil_load_latent',value_kwh)
      # get cop2
      mean_cop2 = evaporator_coil_load/compressor_and_outdoor_fan
      runner.registerValue('ann_mean_cop2',mean_cop2)
      # get idb
      key_value =  "ZONE ONE"
      variable_name = "Zone Mean Air Temperature"
      timeseries_hash = process_output_timeseries(sqlFile, runner, ann_env_pd, 'Hourly', variable_name, key_value)
      runner.registerValue('ann_mean_idb',timeseries_hash[:avg])
      # get humidity_ratio
      variable_name = "Zone Mean Air Humidity Ratio"
      timeseries_hash = process_output_timeseries(sqlFile, runner, ann_env_pd, 'Hourly', variable_name, key_value)
      runner.registerValue('ann_mean_zone_humidity_ratio',timeseries_hash[:avg])
      # get relative_humidity
      variable_name = "Zone Air Relative Humidity"
      timeseries_hash = process_output_timeseries(sqlFile, runner, ann_env_pd, 'Hourly', variable_name, key_value)
      runner.registerValue('ann_mean_zone_relative_humidity',timeseries_hash[:avg])
      # get site avg odb
      key_value =  "Environment"
      variable_name = "Site Outdoor Air Drybulb Temperature"
      timeseries_hash = process_output_timeseries(sqlFile, runner, ann_env_pd, 'Hourly', variable_name, key_value)
      runner.registerValue('ann_mean_odb',timeseries_hash[:avg])
      # get site avg humidity ratio
      variable_name = "Site Outdoor Air Humidity Ratio"
      timeseries_hash = process_output_timeseries(sqlFile, runner, ann_env_pd, 'Hourly', variable_name, key_value)
      runner.registerValue('ann_mean_outdoor_humidity_ratio',timeseries_hash[:avg])

      # populate may_sept data
      # get clg_energy_consumption_total
      key_value =  "BESTEST CE AIR LOOP"
      variable_name = "Air System Electric Energy"
      timeseries_hash = process_output_timeseries(sqlFile, runner, ann_env_pd, 'Hourly', variable_name, key_value,120,92)
      value_kwh = OpenStudio.convert(timeseries_hash[:sum],'J','kWh').get
      runner.registerValue('may_sept_sum_clg_consumption_total',value_kwh)
      # get clg_energy_consumption_compressor (this includes the compressor fan)
      variable_name = "Air System DX Cooling Coil Electric Energy"
      timeseries_hash = process_output_timeseries(sqlFile, runner, ann_env_pd, 'Hourly', variable_name, key_value,120,92)
      value_kwh = OpenStudio.convert(timeseries_hash[:sum],'J','kWh').get
      # store avg value for cop2
      compressor_and_outdoor_fan = value_kwh
      runner.registerValue('may_sept_sum_clg_consumption_compressor',value_kwh)
      variable_name = "Air System Fan Electric Energy"
      timeseries_hash = process_output_timeseries(sqlFile, runner, ann_env_pd, 'Hourly', variable_name, key_value,120,92)
      value_kwh = OpenStudio.convert(timeseries_hash[:sum],'J','kWh').get
      runner.registerValue('may_sept_sum_clg_consumption_indoor_fan',value_kwh)
      # get clg_energy_consumption_supply_fan (can't calculate this)
      runner.registerValue('may_sept_sum_clg_consumption_cond_fan','tbd')
      # get evaporator_coil_load_total
      key_value =  "COIL COOLING DX SINGLE SPEED 1"
      variable_name = "Cooling Coil Total Cooling Rate"
      timeseries_hash = process_output_timeseries(sqlFile, runner, ann_env_pd, 'Hourly', variable_name, key_value,120,92)
      value_kwh = OpenStudio.convert(timeseries_hash[:sum],'Wh','kWh').get
      # store avg value for cop2
      evaporator_coil_load = value_kwh
      runner.registerValue('may_sept_sum_evap_coil_load_total',value_kwh)
      # get evaporator_coil_load_sensible
      variable_name = "Cooling Coil Sensible Cooling Rate"
      timeseries_hash = process_output_timeseries(sqlFile, runner, ann_env_pd, 'Hourly', variable_name, key_value,120,92)
      value_kwh = OpenStudio.convert(timeseries_hash[:sum],'Wh','kWh').get
      runner.registerValue('may_sept_sum_evap_coil_load_sensible',value_kwh)
      # get evaporator_coil_load_latent
      variable_name = "Cooling Coil Latent Cooling Rate"
      timeseries_hash = process_output_timeseries(sqlFile, runner, ann_env_pd, 'Hourly', variable_name, key_value,120,92)
      value_kwh = OpenStudio.convert(timeseries_hash[:sum],'Wh','kWh').get
      runner.registerValue('may_sept_sum_evap_coil_load_latent',value_kwh)
      # get cop2
      mean_cop2 = evaporator_coil_load/compressor_and_outdoor_fan
      runner.registerValue('may_sept_mean_cop2',mean_cop2)
      # get idb
      key_value =  "ZONE ONE"
      variable_name = "Zone Mean Air Temperature"
      timeseries_hash = process_output_timeseries(sqlFile, runner, ann_env_pd, 'Hourly', variable_name, key_value,120,92)
      runner.registerValue('may_sept_mean_idb',timeseries_hash[:avg])
      # get humidity_ratio
      variable_name = "Zone Mean Air Humidity Ratio"
      timeseries_hash = process_output_timeseries(sqlFile, runner, ann_env_pd, 'Hourly', variable_name, key_value,120,92)
      runner.registerValue('may_sept_mean_zone_humidity_ratio',timeseries_hash[:avg])
      # get relative_humidity
      variable_name = "Zone Air Relative Humidity"
      timeseries_hash = process_output_timeseries(sqlFile, runner, ann_env_pd, 'Hourly', variable_name, key_value,120,92)
      runner.registerValue('may_sept_mean_zone_relative_humidity',timeseries_hash[:avg])
      # get site avg odb
      key_value =  "Environment"
      variable_name = "Site Outdoor Air Drybulb Temperature"
      timeseries_hash = process_output_timeseries(sqlFile, runner, ann_env_pd, 'Hourly', variable_name, key_value,120,92)
      runner.registerValue('may_sept_mean_odb',timeseries_hash[:avg])
      # get site avg humidity ratio
      variable_name = "Site Outdoor Air Humidity Ratio"
      timeseries_hash = process_output_timeseries(sqlFile, runner, ann_env_pd, 'Hourly', variable_name, key_value,120,92)
      runner.registerValue('may_sept_mean_outdoor_humidity_ratio',timeseries_hash[:avg])

      # Annual Hourly Integrated Maxima Consumptions and Loads Table

      # get supply_fan
      key_value =  "BESTEST CE AIR LOOP"
      variable_name = "Air System Electric Energy"
      timeseries_hash = process_output_timeseries(sqlFile, runner, ann_env_pd, 'Hourly', variable_name, key_value)
      value_wh = OpenStudio.convert(timeseries_hash[:max],'J','Wh').get
      runner.registerValue('energy_consumption_comp_both_fans_wh',value_wh)
      runner.registerValue('energy_consumption_comp_both_fans_date',date_time_parse(timeseries_hash[:max_date_time])[0])
      runner.registerValue('energy_consumption_comp_both_fans_hr',date_time_parse(timeseries_hash[:max_date_time])[1])

      # get evaporator_coil
      key_value =  "COIL COOLING DX SINGLE SPEED 1"
      variable_name = "Cooling Coil Sensible Cooling Rate"
      timeseries_hash = process_output_timeseries(sqlFile, runner, ann_env_pd, 'Hourly', variable_name, key_value)
      value_wh = OpenStudio.convert(timeseries_hash[:max],'Wh','Wh').get
      runner.registerValue('evap_coil_load_sensible_wh',value_wh)
      runner.registerValue('evap_coil_load_sensible_date',date_time_parse(timeseries_hash[:max_date_time])[0])
      runner.registerValue('evap_coil_load_sensible_hr',date_time_parse(timeseries_hash[:max_date_time])[1])
      variable_name = "Cooling Coil Latent Cooling Rate"
      timeseries_hash = process_output_timeseries(sqlFile, runner, ann_env_pd, 'Hourly', variable_name, key_value)
      value_wh = OpenStudio.convert(timeseries_hash[:max],'Wh','Wh').get
      runner.registerValue('evap_coil_load_latent_wh',value_wh)
      runner.registerValue('evap_coil_load_latent_date',date_time_parse(timeseries_hash[:max_date_time])[0])
      runner.registerValue('evap_coil_load_latent_hr',date_time_parse(timeseries_hash[:max_date_time])[1])
      variable_name = "Cooling Coil Total Cooling Rate"
      timeseries_hash = process_output_timeseries(sqlFile, runner, ann_env_pd, 'Hourly', variable_name, key_value)
      value_wh = OpenStudio.convert(timeseries_hash[:max],'Wh','Wh').get
      runner.registerValue('evap_coil_load_sensible_and_latent_wh',value_wh)
      runner.registerValue('evap_coil_load_sensible_and_latent_date',date_time_parse(timeseries_hash[:max_date_time])[0])
      runner.registerValue('evap_coil_load_sensible_and_latent_hr',date_time_parse(timeseries_hash[:max_date_time])[1])

      key_value =  "Environment"
      variable_name = "Site Outdoor Air Drybulb Temperature"
      timeseries_hash = process_output_timeseries(sqlFile, runner, ann_env_pd, 'Hourly', variable_name, key_value)
      runner.registerValue('weather_odb_c',timeseries_hash[:max])
      runner.registerValue('weather_odb_date',date_time_parse(timeseries_hash[:max_date_time])[0])
      runner.registerValue('weather_odb_hr',date_time_parse(timeseries_hash[:max_date_time])[1])
      variable_name = "Site Outdoor Air Humidity Ratio"
      timeseries_hash = process_output_timeseries(sqlFile, runner, ann_env_pd, 'Hourly', variable_name, key_value)
      runner.registerValue('weather_outdoor_humidity_ratio_c',timeseries_hash[:max])
      runner.registerValue('weather_outdoor_humidity_ratio_date',date_time_parse(timeseries_hash[:max_date_time])[0])
      runner.registerValue('weather_outdoor_humidity_ratio_hr',date_time_parse(timeseries_hash[:max_date_time])[1])

      # Annual Hourly Integrated Maxima - COP2 and Zone Table

      # get clg_energy_consumption_total (for cop calc)
      key_value =  "BESTEST CE AIR LOOP"
      variable_name = "Air System Electric Energy"
      timeseries_hash = process_output_timeseries(sqlFile, runner, ann_env_pd, 'Hourly', variable_name, key_value)
      total_cooling_energy_consumption_j_array = timeseries_hash[:array]
      # get zone_load_total (for net_refrigeration_effect_w)
      key_value =  "AIR LOOP HVAC UNITARY SYSTEM 1"
      variable_name = "Unitary System Total Cooling Rate"
      timeseries_hash = process_output_timeseries(sqlFile, runner, ann_env_pd, 'Hourly', variable_name, key_value)
      net_refrigeration_effect_w_array = timeseries_hash[:array]
      # calculate 8760 cop
      cop_8760 = []
      total_cooling_energy_consumption_j_array.size.times.each do |i|
        if total_cooling_energy_consumption_j_array[i] > 0.0
          cop_8760 << net_refrigeration_effect_w_array[i] / (total_cooling_energy_consumption_j_array[i]/3600.0) # W = J/s
        else
          cop_8760 << 0.0 # don't like putting value here but if I don't put value can't get min and max, and if I skip entry index position will be wrong
        end
      end
      index_of_max = cop_8760.each_index.max
      index_of_min = cop_8760.each_index.min
      runner.registerValue('cop2_max_cop2',cop_8760.max)
      runner.registerValue('cop2_max_date',return_date_time_from_8760_index(index_of_max)[0])
      runner.registerValue('cop2_max_hr',return_date_time_from_8760_index(index_of_max)[1])
      runner.registerValue('cop2_min_cop2',cop_8760.min)
      runner.registerValue('cop2_min_date',return_date_time_from_8760_index(index_of_min)[0])
      runner.registerValue('cop2_min_hr',return_date_time_from_8760_index(index_of_min)[1])
      # get idb
      key_value =  "ZONE ONE"
      variable_name = "Zone Mean Air Temperature"
      timeseries_hash = process_output_timeseries(sqlFile, runner, ann_env_pd, 'Hourly', variable_name, key_value)
      runner.registerValue('idb_max_idb',timeseries_hash[:max])
      runner.registerValue('idb_max_date',date_time_parse(timeseries_hash[:max_date_time])[0])
      runner.registerValue('idb_max_hr',date_time_parse(timeseries_hash[:max_date_time])[1])
      runner.registerValue('idb_min_idb',timeseries_hash[:min])
      runner.registerValue('idb_min_date',date_time_parse(timeseries_hash[:min_date_time])[0])
      runner.registerValue('idb_min_hr',date_time_parse(timeseries_hash[:min_date_time])[1])
      # get humidity_ratio
      variable_name = "Zone Mean Air Humidity Ratio"
      timeseries_hash = process_output_timeseries(sqlFile, runner, ann_env_pd, 'Hourly', variable_name, key_value)
      runner.registerValue('hr_max_humidity_ratio',timeseries_hash[:max])
      runner.registerValue('hr_max_date',date_time_parse(timeseries_hash[:max_date_time])[0])
      runner.registerValue('hr_max_hr',date_time_parse(timeseries_hash[:max_date_time])[1])
      runner.registerValue('hr_min_humidity_ratio',timeseries_hash[:min])
      runner.registerValue('hr_min_date',date_time_parse(timeseries_hash[:min_date_time])[0])
      runner.registerValue('hr_min_hr',date_time_parse(timeseries_hash[:min_date_time])[1])
      # get relative_humidity
      variable_name = "Zone Air Relative Humidity"
      timeseries_hash = process_output_timeseries(sqlFile, runner, ann_env_pd, 'Hourly', variable_name, key_value)
      runner.registerValue('rh_max_relative_humidity',timeseries_hash[:max])
      runner.registerValue('rh_max_date',date_time_parse(timeseries_hash[:max_date_time])[0])
      runner.registerValue('rh_max_hr',date_time_parse(timeseries_hash[:max_date_time])[1])
      runner.registerValue('rh_min_relative_humidity',timeseries_hash[:min])
      runner.registerValue('rh_min_date',date_time_parse(timeseries_hash[:min_date_time])[0])
      runner.registerValue('rh_min_hr',date_time_parse(timeseries_hash[:min_date_time])[1])

      # populate april_dec data
      # get clg_energy_consumption_total (for cop calc)
      key_value =  "BESTEST CE AIR LOOP"
      variable_name = "Air System Electric Energy"
      timeseries_hash = process_output_timeseries(sqlFile, runner, ann_env_pd, 'Hourly', variable_name, key_value,90)
      total_cooling_energy_consumption_j_array = timeseries_hash[:array]
      # get zone_load_total (for net_refrigeration_effect_w)
      key_value =  "AIR LOOP HVAC UNITARY SYSTEM 1"
      variable_name = "Unitary System Total Cooling Rate"
      timeseries_hash = process_output_timeseries(sqlFile, runner, ann_env_pd, 'Hourly', variable_name, key_value,90)
      net_refrigeration_effect_w_array = timeseries_hash[:array]
      # calculate 8760 cop
      cop_8760 = []
      total_cooling_energy_consumption_j_array.size.times.each do |i|
        if total_cooling_energy_consumption_j_array[i] > 0.0
          cop_8760 << net_refrigeration_effect_w_array[i] / (total_cooling_energy_consumption_j_array[i]/3600.0) # W = J/s
        else
          cop_8760 << 0.0 # don't like putting value here but if I don't put value can't get min and max, and if I skip entry index position will be wrong
        end
      end
      index_of_max = cop_8760.each_index.max
      index_of_min = cop_8760.each_index.min
      runner.registerValue('apr_dec_cop2_max_cop2',cop_8760.max)
      runner.registerValue('apr_dec_cop2_max_date',return_date_time_from_8760_index(index_of_max)[0])
      runner.registerValue('apr_dec_cop2_max_hr',return_date_time_from_8760_index(index_of_max)[1])
      runner.registerValue('apr_dec_cop2_min_cop2',cop_8760.min)
      runner.registerValue('apr_dec_cop2_min_date',return_date_time_from_8760_index(index_of_min)[0])
      runner.registerValue('apr_dec_cop2_min_hr',return_date_time_from_8760_index(index_of_min)[1])
      # get idb
      key_value =  "ZONE ONE"
      variable_name = "Zone Mean Air Temperature"
      timeseries_hash = process_output_timeseries(sqlFile, runner, ann_env_pd, 'Hourly', variable_name, key_value,90)
      runner.registerValue('apr_dec_idb_max_idb',timeseries_hash[:max])
      runner.registerValue('apr_dec_idb_max_date',date_time_parse(timeseries_hash[:max_date_time])[0])
      runner.registerValue('apr_dec_idb_max_hr',date_time_parse(timeseries_hash[:max_date_time])[1])
      runner.registerValue('apr_dec_idb_min_idb',timeseries_hash[:min])
      runner.registerValue('apr_dec_idb_min_date',date_time_parse(timeseries_hash[:min_date_time])[0])
      runner.registerValue('apr_dec_idb_min_hr',date_time_parse(timeseries_hash[:min_date_time])[1])
      # get humidity_ratio
      variable_name = "Zone Mean Air Humidity Ratio"
      timeseries_hash = process_output_timeseries(sqlFile, runner, ann_env_pd, 'Hourly', variable_name, key_value,90)
      runner.registerValue('apr_dec_hr_max_humidity_ratio',timeseries_hash[:max])
      runner.registerValue('apr_dec_hr_max_date',date_time_parse(timeseries_hash[:max_date_time])[0])
      runner.registerValue('apr_dec_hr_max_hr',date_time_parse(timeseries_hash[:max_date_time])[1])
      runner.registerValue('apr_dec_hr_min_humidity_ratio',timeseries_hash[:min])
      runner.registerValue('apr_dec_hr_min_date',date_time_parse(timeseries_hash[:min_date_time])[0])
      runner.registerValue('apr_dec_hr_min_hr',date_time_parse(timeseries_hash[:min_date_time])[1])
      # get relative_humidity
      variable_name = "Zone Air Relative Humidity"
      timeseries_hash = process_output_timeseries(sqlFile, runner, ann_env_pd, 'Hourly', variable_name, key_value,90)
      runner.registerValue('apr_dec_rh_max_relative_humidity',timeseries_hash[:max])
      runner.registerValue('apr_dec_rh_max_date',date_time_parse(timeseries_hash[:max_date_time])[0])
      runner.registerValue('apr_dec_rh_max_hr',date_time_parse(timeseries_hash[:max_date_time])[1])
      runner.registerValue('apr_dec_rh_min_relative_humidity',timeseries_hash[:min])
      runner.registerValue('apr_dec_rh_min_date',date_time_parse(timeseries_hash[:min_date_time])[0])
      runner.registerValue('apr_dec_rh_min_hr',date_time_parse(timeseries_hash[:min_date_time])[1])

      # loop to gather hourly data as string from 0628
      def hourly_values(output_timeseries,target_date,source_unit = '',target_unit = '')

        hourly_single_day_array = []
        24.times.each do |i|
          date_string = "#{target_date} #{i+1}:00:00.000"
          date_time = OpenStudio::DateTime.new(date_string)
          val_at_date_time = output_timeseries.get.value(date_time)
          value = OpenStudio.convert(val_at_date_time, source_unit, target_unit).get
          hourly_single_day_array << value

        end
        hourly_single_day_array = hourly_single_day_array.join(',')

        return hourly_single_day_array

      end

      # loop to gather hourly data as string from 0628
      def avg_from_hourly_values(output_timeseries,target_date,source_unit = '',target_unit = '')

        array = hourly_values(output_timeseries,target_date,source_unit,target_unit).split(',')
        array.map! {|item| item.to_f}
        avg = array.reduce(0, :+)/array.size

        return avg

      end

      # Case 300 June 28th Hourly Table

      # get clg_energy_consumption_compressor
      key_value =  "BESTEST CE AIR LOOP"
      variable_name = "Air System DX Cooling Coil Electric Energy"
      output_timeseries = sqlFile.timeSeries(ann_env_pd, 'Hourly', variable_name, key_value)
      runner.registerValue('0628_hourly_energy_consumpton_compressor',hourly_values(output_timeseries,'2009-06-28','J','Wh'))
      # get clg_energy_consumption_supply_fan (can't calculate)
      runner.registerValue('0628_hourly_energy_consumpton_cond_fan','tbd')
      # get evaporator_coil_load_total
      key_value =  "COIL COOLING DX SINGLE SPEED 1"
      variable_name = "Cooling Coil Total Cooling Rate"
      output_timeseries = sqlFile.timeSeries(ann_env_pd, 'Hourly', variable_name, key_value)
      runner.registerValue('0628_hourly_evaporator_coil_load_total',hourly_values(output_timeseries,'2009-06-28'))
      # get evaporator_coil_load_sensible
      variable_name = "Cooling Coil Sensible Cooling Rate"
      output_timeseries = sqlFile.timeSeries(ann_env_pd, 'Hourly', variable_name, key_value)
      runner.registerValue('0628_hourly_evaporator_coil_load_sensible',hourly_values(output_timeseries,'2009-06-28'))
      # get evaporator_coil_load_latent
      variable_name = "Cooling Coil Latent Cooling Rate"
      output_timeseries = sqlFile.timeSeries(ann_env_pd, 'Hourly', variable_name, key_value)
      runner.registerValue('0628_hourly_evaporator_coil_load_latent',hourly_values(output_timeseries,'2009-06-28'))
      # get humidity_ratio
      key_value =  "ZONE ONE"
      variable_name = "Zone Mean Air Humidity Ratio"
      output_timeseries = sqlFile.timeSeries(ann_env_pd, 'Hourly', variable_name, key_value)
      runner.registerValue('0628_hourly_zone_humidity_ratio',hourly_values(output_timeseries,'2009-06-28'))

      # get clg_energy_consumption_total (for cop calc)
      key_value =  "BESTEST CE AIR LOOP"
      variable_name = "Air System Electric Energy"
      output_timeseries = sqlFile.timeSeries(ann_env_pd, 'Hourly', variable_name, key_value)
      total_cooling_energy_consumption_j_array = hourly_values(output_timeseries,'2009-06-28').split(",")
      # get zone_load_total (for net_refrigeration_effect_w)
      key_value =  "AIR LOOP HVAC UNITARY SYSTEM 1"
      variable_name = "Unitary System Total Cooling Rate"
      output_timeseries = sqlFile.timeSeries(ann_env_pd, 'Hourly', variable_name, key_value)
      net_refrigeration_effect_w_array = hourly_values(output_timeseries,'2009-06-28').split(",")
      # calculate 24 cop
      cop_24 = []
      total_cooling_energy_consumption_j_array.size.times.each do |i|
        cop_24 << net_refrigeration_effect_w_array[i].to_f / (total_cooling_energy_consumption_j_array[i].to_f/3600.0) # W = J/s
      end
      runner.registerValue('0628_hourly_cop2',cop_24.join(","))

      # get site odb
      key_value =  "Environment"
      variable_name = "Site Outdoor Air Drybulb Temperature"
      output_timeseries = sqlFile.timeSeries(ann_env_pd, 'Hourly', variable_name, key_value)
      runner.registerValue('0628_hourly_odb',hourly_values(output_timeseries,'2009-06-28'))

      # get terminal drybulb and wetbulb
      key_value =  "NODE 6"
      variable_name = "System Node Temperature"
      output_timeseries = sqlFile.timeSeries(ann_env_pd, 'Hourly', variable_name, key_value)
      runner.registerValue('0628_hourly_edb',hourly_values(output_timeseries,'2009-06-28'))
      key_value =  "NODE 6"
      variable_name = "System Node Wetbulb Temperature"
      output_timeseries = sqlFile.timeSeries(ann_env_pd, 'Hourly', variable_name, key_value)
      runner.registerValue('0628_hourly_ewb',hourly_values(output_timeseries,'2009-06-28'))

      # get site avg humidity ratio
      key_value =  "Environment"
      variable_name = "Site Outdoor Air Humidity Ratio"
      output_timeseries = sqlFile.timeSeries(ann_env_pd, 'Hourly', variable_name, key_value)
      runner.registerValue('0628_hourly_outdoor_humidity_ratio',hourly_values(output_timeseries,'2009-06-28'))

      # Case 500 and 530 Average Daily Outputs

      # get clg_energy_consumption_total
      key_value =  "BESTEST CE AIR LOOP"
      variable_name = "Air System Electric Energy"
      output_timeseries = sqlFile.timeSeries(ann_env_pd, 'Hourly', variable_name, key_value)
      avg = avg_from_hourly_values(output_timeseries,'2009-04-30','J', 'Wh')
      runner.registerValue('0430_day_energy_consumption_total',avg)
      avg = avg_from_hourly_values(output_timeseries,'2009-06-25','J', 'Wh')
      runner.registerValue('0625_day_energy_consumption_total',avg)
      # get clg_energy_consumption_compressor
      variable_name = "Air System DX Cooling Coil Electric Energy"
      output_timeseries = sqlFile.timeSeries(ann_env_pd, 'Hourly', variable_name, key_value)
      avg = avg_from_hourly_values(output_timeseries,'2009-04-30','J', 'Wh')
      runner.registerValue('0430_day_energy_consumption_compressor',avg)
      avg = avg_from_hourly_values(output_timeseries,'2009-06-25','J', 'Wh')
      runner.registerValue('0625_day_energy_consumption_compressor',avg)
      # get clg_energy_consumption_supply_fan
      variable_name = "Air System Fan Electric Energy"
      output_timeseries = sqlFile.timeSeries(ann_env_pd, 'Hourly', variable_name, key_value)
      avg = avg_from_hourly_values(output_timeseries,'2009-04-30','J', 'Wh')
      runner.registerValue('0430_day_energy_consumption_supply_fan',avg)
      avg = avg_from_hourly_values(output_timeseries,'2009-06-25','J', 'Wh')
      runner.registerValue('0625_day_energy_consumption_supply_fan',avg)

      runner.registerValue('0430_day_energy_consumption_condenser_fan','tbd')
      runner.registerValue('0625_day_energy_consumption_condenser_fan','tbd')

      # get evaporator_coil_load_total
      key_value =  "COIL COOLING DX SINGLE SPEED 1"
      variable_name = "Cooling Coil Total Cooling Rate"
      output_timeseries = sqlFile.timeSeries(ann_env_pd, 'Hourly', variable_name, key_value)
      avg = avg_from_hourly_values(output_timeseries,'2009-04-30')
      runner.registerValue('0430_day_evaporator_coil_load_total',avg)
      avg = avg_from_hourly_values(output_timeseries,'2009-06-25')
      runner.registerValue('0625_day_evaporator_coil_load_total',avg)
      # get evaporator_coil_load_sensible
      variable_name = "Cooling Coil Sensible Cooling Rate"
      output_timeseries = sqlFile.timeSeries(ann_env_pd, 'Hourly', variable_name, key_value)
      avg = avg_from_hourly_values(output_timeseries,'2009-04-30')
      runner.registerValue('0430_day_evaporator_coil_load_sensible',avg)
      avg = avg_from_hourly_values(output_timeseries,'2009-06-25')
      runner.registerValue('0625_day_evaporator_coil_load_sensible',avg)
      # get evaporator_coil_load_latent
      variable_name = "Cooling Coil Latent Cooling Rate"
      output_timeseries = sqlFile.timeSeries(ann_env_pd, 'Hourly', variable_name, key_value)
      avg = avg_from_hourly_values(output_timeseries,'2009-04-30')
      runner.registerValue('0430_day_evaporator_coil_load_latent',avg)
      avg = avg_from_hourly_values(output_timeseries,'2009-06-25')
      runner.registerValue('0625_day_evaporator_coil_load_latent',avg)

      # get humidity_ratio
      key_value =  "ZONE ONE"
      variable_name = "Zone Mean Air Humidity Ratio"
      output_timeseries = sqlFile.timeSeries(ann_env_pd, 'Hourly', variable_name, key_value)
      avg = avg_from_hourly_values(output_timeseries,'2009-04-30')
      runner.registerValue('0430_day_zone_humidity_ratio',avg)
      avg = avg_from_hourly_values(output_timeseries,'2009-06-25')
      runner.registerValue('0625_day_zone_humidity_ratio',avg)

      # get clg_energy_consumption_total (for cop calc)
      key_value =  "BESTEST CE AIR LOOP"
      variable_name = "Air System Electric Energy"
      output_timeseries = sqlFile.timeSeries(ann_env_pd, 'Hourly', variable_name, key_value)
      total_cooling_energy_consumption_j_array = hourly_values(output_timeseries,'2009-04-30').split(",")
      # get zone_load_total (for net_refrigeration_effect_w)
      key_value =  "AIR LOOP HVAC UNITARY SYSTEM 1"
      variable_name = "Unitary System Total Cooling Rate"
      output_timeseries = sqlFile.timeSeries(ann_env_pd, 'Hourly', variable_name, key_value)
      net_refrigeration_effect_w_array = hourly_values(output_timeseries,'2009-04-30').split(",")
      # calculate 24 cop
      cop_24 = []
      total_cooling_energy_consumption_j_array.size.times.each do |i|
        cop_24 << net_refrigeration_effect_w_array[i].to_f / (total_cooling_energy_consumption_j_array[i].to_f/3600.0) # W = J/s
      end
      runner.registerValue('0430_day_cop2',cop_24.reduce(0, :+)/cop_24.size)

      # get clg_energy_consumption_total (for cop calc)
      key_value =  "BESTEST CE AIR LOOP"
      variable_name = "Air System Electric Energy"
      output_timeseries = sqlFile.timeSeries(ann_env_pd, 'Hourly', variable_name, key_value)
      total_cooling_energy_consumption_j_array = hourly_values(output_timeseries,'2009-06-25').split(",")
      # get zone_load_total (for net_refrigeration_effect_w)
      key_value =  "AIR LOOP HVAC UNITARY SYSTEM 1"
      variable_name = "Unitary System Total Cooling Rate"
      output_timeseries = sqlFile.timeSeries(ann_env_pd, 'Hourly', variable_name, key_value)
      net_refrigeration_effect_w_array = hourly_values(output_timeseries,'2009-06-25').split(",")
      # calculate 24 cop
      cop_24 = []
      total_cooling_energy_consumption_j_array.size.times.each do |i|
        cop_24 << net_refrigeration_effect_w_array[i].to_f / (total_cooling_energy_consumption_j_array[i].to_f/3600.0) # W = J/s
      end
      runner.registerValue('0625_day_cop2',cop_24.reduce(0, :+)/cop_24.size)

      # get site avg odb
      key_value =  "Environment"
      variable_name = "Site Outdoor Air Drybulb Temperature"
      output_timeseries = sqlFile.timeSeries(ann_env_pd, 'Hourly', variable_name, key_value)
      avg = avg_from_hourly_values(output_timeseries,'2009-04-30')
      runner.registerValue('0430_day_odb',avg)
      avg = avg_from_hourly_values(output_timeseries,'2009-06-25')
      runner.registerValue('0625_day_odb',avg)
      key_value =  "NODE 6"
      variable_name = "System Node Temperature"
      output_timeseries = sqlFile.timeSeries(ann_env_pd, 'Hourly', variable_name, key_value)
      avg = avg_from_hourly_values(output_timeseries,'2009-04-30')
      runner.registerValue('0430_day_edb',avg)
      key_value =  "NODE 6"
      variable_name = "System Node Wetbulb Temperature"
      output_timeseries = sqlFile.timeSeries(ann_env_pd, 'Hourly', variable_name, key_value)
      avg = avg_from_hourly_values(output_timeseries,'2009-06-25')
      runner.registerValue('0625_day_edb',avg)

    end

    # close the sql file
    sqlFile.close()

    return true
 
  end

end

# register the measure to be used by the application
BESTESTCEReporting.new.registerWithApplication
