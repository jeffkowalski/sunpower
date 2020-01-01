#!/usr/bin/env ruby
# frozen_string_literal: true

require 'thor'
require 'fileutils'
require 'logger'
require 'rest-client'
require 'json'
require 'yaml'
require 'influxdb'

LOGFILE = File.join(Dir.home, '.log', 'sunpower.log')
CREDENTIALS_PATH = File.join(Dir.home, '.credentials', 'sunpower.yaml')

API_BASE_URL = 'https://elhapi.edp.sunpower.com/v1/elh'

class String
  def numeric?
    !Float(self).nil?
  rescue StandardError
    false
  end
end

class Sunpower < Thor
  no_commands do
    def redirect_output
      unless LOGFILE == 'STDOUT'
        logfile = File.expand_path(LOGFILE)
        FileUtils.mkdir_p(File.dirname(logfile), mode: 0o755)
        FileUtils.touch logfile
        File.chmod 0o644, logfile
        $stdout.reopen logfile, 'a'
      end
      $stderr.reopen $stdout
      $stdout.sync = $stderr.sync = true
    end

    def setup_logger
      redirect_output if options[:log]

      @logger = Logger.new STDOUT
      @logger.level = options[:verbose] ? Logger::DEBUG : Logger::INFO
      @logger.info 'starting'
    end
  end

  no_commands do
    def authorize
      sunpower_credentials = YAML.load_file CREDENTIALS_PATH
      response = RestClient.post "#{API_BASE_URL}/authenticate",
                                 sunpower_credentials.to_json,
                                 'Content-Type' => 'application/json'
      authorization = JSON.parse response
      @logger.debug authorization
      authorization
    end

    def get_current_power(authorization)
      response = RestClient.get "#{API_BASE_URL}/address/#{authorization['addressId']}/power",
                                Authorization: "SP-CUSTOM #{authorization['tokenID']}",
                                params: { async: false }
      @logger.debug response.headers
      @logger.info response
      power = JSON.parse response
      # TODO: find the actual date of the reading
      # this hack below is certainly incorrect
      power['Date'] = response.headers[:date]
      power
    end
  end

  class_option :log,     type: :boolean, default: true, desc: "log output to #{LOGFILE}"
  class_option :verbose, type: :boolean, aliases: '-v', desc: 'increase verbosity'

  desc 'describe-status', 'describe the current state of the solar panel array'
  def describe_status
    setup_logger

    authorization = authorize
    power = get_current_power authorization
    puts "#{power['CurrentProduction']}kW at #{power['Date']}"

    #    hourly_energy_data = RestClient.get "#{API_BASE_URL}/SystemInfo/SystemInfo.svc/getHourlyEnergyData?tokenid=#{tokenid}&timestamp=#{TIMESTAMP}"
    #    energy_data = csv_to_hash_table hourly_energy_data
    #    lifetime_energy = energy_data.map { |_date, values| values[:ep] }.reduce(0, :+)
    #    puts "Lifetime energy = #{lifetime_energy} kWh"
  end

  desc 'record-status', 'record the current solar production to database'
  method_option :dry_run, type: :boolean, aliases: '-d', desc: 'do not write to database'
  def record_status
    setup_logger
    begin
      authorization = authorize
      power = get_current_power authorization

      influxdb = InfluxDB::Client.new 'sunpower'

      data = {
        values: { value: power['CurrentProduction'].to_f },
        timestamp: (Time.parse power['Date']).to_i
      }
      influxdb.write_point('production', data) unless options[:dry_run]
    rescue StandardError => e
      @logger.error e
    end
  end
end

Sunpower.start
