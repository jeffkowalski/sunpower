#!/usr/bin/env ruby

require 'net/http'
require 'uri'
require 'open-uri'
require 'json'
require 'yaml/store'


sunpower_credentials = YAML.load_file File.join(Dir.home, '.credentials', "sunpower.yaml")
api_base_url = "https://monitor.us.sunpower.com/CustomerPortal/"

uri = URI.parse(api_base_url + "Auth/Auth.svc/Authenticate")
http = Net::HTTP.new uri.hostname, uri.port
http.use_ssl = true
auth_response = http.send_request 'POST', uri.path, sunpower_credentials.to_json, {'Content-Type' => 'application/json'}
puts auth_response.body
decoded = JSON.parse auth_response.body

tokenid = decoded['Payload']['TokenID']

current_power_response = open(api_base_url + "CurrentPower/CurrentPower.svc/GetCurrentPower?id=#{tokenid}").read
puts current_power_response
decoded = JSON.parse current_power_response
puts "#{decoded['Payload']['CurrentProduction']}kW at #{decoded['Payload']['SystemList'][0]['DateTimeReceived']}"

class String
  def numeric?
    Float(self) != nil rescue false
  end
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

TIMESTAMP = '2000-01-01T00:00:00' # long ago
hourly_energy_data = open(api_base_url + "SystemInfo/SystemInfo.svc/getHourlyEnergyData?tokenid=#{tokenid}&timestamp=#{TIMESTAMP}").read
energy_data = csvToHashtable hourly_energy_data
puts "Lifetime energy = #{energy_data.map{ |date, values| values[:ep] }.reduce(0, :+)} kWh"
