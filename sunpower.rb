#!/usr/bin/env ruby

require 'thor'
require 'fileutils'
require 'logger'
require 'rest-client'
require 'json'
require 'yaml'
require 'influxdb'


LOGFILE = File.join(Dir.home, '.log', 'sunpower.log')
CREDENTIALS_PATH = File.join(Dir.home, '.credentials', "sunpower.yaml")

TIMESTAMP = '2000-01-01T00:00:00' # long ago
API_BASE_URL = "https://monitor.us.sunpower.com/CustomerPortal"

class String
  def numeric?
    Float(self) != nil rescue false
  end
end

class Sunpower < Thor
  no_commands {
    def redirect_output
      unless LOGFILE == 'STDOUT'
        logfile = File.expand_path(LOGFILE)
        FileUtils.mkdir_p(File.dirname(logfile), :mode => 0755)
        FileUtils.touch logfile
        File.chmod 0644, logfile
        $stdout.reopen logfile, 'a'
      end
      $stderr.reopen $stdout
      $stdout.sync = $stderr.sync = true
    end

    def setup_logger
      redirect_output if options[:log]

      $logger = Logger.new STDOUT
      $logger.level = options[:verbose] ? Logger::DEBUG : Logger::INFO
      $logger.info 'starting'
    end
  }

  no_commands {
    def authorize
      sunpower_credentials = YAML.load_file CREDENTIALS_PATH
      response = RestClient.post "#{API_BASE_URL}/Auth/Auth.svc/Authenticate", sunpower_credentials.to_json, {'Content-Type' => 'application/json'}
      authorization = JSON.parse response
      tokenid = authorization['Payload']['TokenID']
      return tokenid
    end

    def get_current_power tokenid
      response = RestClient.get "#{API_BASE_URL}/CurrentPower/CurrentPower.svc/GetCurrentPower?id=#{tokenid}"
      $logger.info response
      power = JSON.parse response
      return power
    end

    # similar to https://monitor.us.sunpower.com/v08042016054226/C:/Program Files (x86)/Jenkins/workspace/SunpowerSpa-Development/src/scripts/modules/lifetimeEnergy/lifetimeEnergyService.js#574
    def csvToHashtable csvData
      if csvData.nil? or !csvData.length
        return nil
      end

      rows = csvData.split('|')

      # remove first row if contains column names
      rows.shift() unless rows[0][0].numeric?
      rows.pop() unless rows[rows.length - 1].length

      # now create hashtable from array
      obj = {}
      rows.each { |row|
        a = row.split(',')
        if (a[0].length > 10)
          obj[a[0]] = {
            :ep => a[1].to_f,
            :eu => a[2].to_f,
            :mp => a[3].to_f,
            :i => 3600
          }
        end
      }
      return obj
    end
  }

  class_option :log,     :type => :boolean, :default => true, :desc => "log output to ~/.rainforest.log"
  class_option :verbose, :type => :boolean, :aliases => "-v", :desc => "increase verbosity"

  desc "describe-status", "describe the current state of the solar panel array"
  def describe_status
    setup_logger

    tokenid = authorize
    power = get_current_power tokenid
    puts "#{power['Payload']['CurrentProduction']}kW at #{power['Payload']['SystemList'][0]['DateTimeReceived']}"

    hourly_energy_data = RestClient.get "#{API_BASE_URL}/SystemInfo/SystemInfo.svc/getHourlyEnergyData?tokenid=#{tokenid}&timestamp=#{TIMESTAMP}"
    energy_data = csvToHashtable hourly_energy_data
    puts "Lifetime energy = #{energy_data.map{ |_date, values| values[:ep] }.reduce(0, :+)} kWh"
  end

  desc "record-status", "record the current state of the pool to database"
  def record_status
    setup_logger

    tokenid = authorize
    power = get_current_power tokenid

    influxdb = InfluxDB::Client.new 'sunpower'

    data = {
      values: { value: power['Payload']['CurrentProduction'].to_f },
      timestamp: (DateTime.parse power['Payload']['SystemList'][0]['DateTimeReceived']).to_time.to_i - Time.now.utc_offset
    }
    influxdb.write_point('production', data)

  end

end

Sunpower.start
