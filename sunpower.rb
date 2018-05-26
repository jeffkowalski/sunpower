#!/usr/bin/env ruby

require 'json'
require 'yaml/store'
require 'rest-client'


sunpower_credentials = YAML.load_file File.join(Dir.home, '.credentials', "sunpower.yaml")
api_base_url = "https://monitor.us.sunpower.com/CustomerPortal"

response = RestClient.post "#{api_base_url}/Auth/Auth.svc/Authenticate", sunpower_credentials.to_json, {'Content-Type' => 'application/json'}
authorization = JSON.parse response
tokenid = authorization['Payload']['TokenID']

response = RestClient.get "#{api_base_url}/CurrentPower/CurrentPower.svc/GetCurrentPower?id=#{tokenid}"
puts response
power = JSON.parse response
puts "#{power['Payload']['CurrentProduction']}kW at #{power['Payload']['SystemList'][0]['DateTimeReceived']}"


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
hourly_energy_data = RestClient.get "#{api_base_url}/SystemInfo/SystemInfo.svc/getHourlyEnergyData?tokenid=#{tokenid}&timestamp=#{TIMESTAMP}"
energy_data = csvToHashtable hourly_energy_data
puts "Lifetime energy = #{energy_data.map{ |_date, values| values[:ep] }.reduce(0, :+)} kWh"
