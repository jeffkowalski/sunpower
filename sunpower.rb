#!/usr/bin/env ruby
# frozen_string_literal: true

require 'rubygems'
require 'bundler/setup'
Bundler.require(:default)

API_BASE_URL = 'https://elhapi.edp.sunpower.com/v1/elh'

class String
  def numeric?
    !Float(self).nil?
  rescue StandardError
    false
  end
end

class Sunpower < RecorderBotBase
  no_commands do
    def authorize
      sunpower_credentials = load_credentials
      response = RestClient.post "#{API_BASE_URL}/authenticate",
                                 sunpower_credentials.to_json,
                                 'Content-Type' => 'application/json'
      authorization = JSON.parse response
      @logger.debug authorization
      authorization
    end

    def get_current_power(authorization)
      response = with_rescue([RestClient::Unauthorized], @logger) do |_try|
        RestClient.get "#{API_BASE_URL}/address/#{authorization['addressId']}/power",
                       Authorization: "SP-CUSTOM #{authorization['tokenID']}",
                       params: { async: false }
      end
      @logger.debug response.headers
      @logger.info response
      power = JSON.parse response
      # TODO: find the actual date of the reading
      # this hack below is certainly incorrect
      power['Date'] = response.headers[:date]
      power
    end
  end

  desc 'describe-status', 'describe the current state of the solar panel array'
  def describe_status
    authorization = authorize
    power = get_current_power authorization
    puts "#{power['CurrentProduction']}kW at #{power['Date']}"

    #    hourly_energy_data = RestClient.get "#{API_BASE_URL}/SystemInfo/SystemInfo.svc/getHourlyEnergyData?tokenid=#{tokenid}&timestamp=#{TIMESTAMP}"
    #    energy_data = csv_to_hash_table hourly_energy_data
    #    lifetime_energy = energy_data.map { |_date, values| values[:ep] }.reduce(0, :+)
    #    puts "Lifetime energy = #{lifetime_energy} kWh"
  end

  no_commands do
    def main
      power = with_rescue([RestClient::GatewayTimeout, RestClient::Exceptions::OpenTimeout, RestClient::InternalServerError], @logger, retries: 6) do |_try|
        authorization = authorize
        get_current_power authorization
      end

      influxdb = InfluxDB::Client.new 'sunpower' unless options[:dry_run]
      data = [{ series: 'production',
                values: { value: power['CurrentProduction'].to_f },
                timestamp: (Time.parse power['Date']).to_i }]
      influxdb.write_points(data) unless options[:dry_run]
    end
  end
end

Sunpower.start
