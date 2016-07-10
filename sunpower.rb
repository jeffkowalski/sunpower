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

current_power_response = open(api_base_url + "CurrentPower/CurrentPower.svc/GetCurrentPower?id=#{decoded['Payload']['TokenID']}").read
puts current_power_response
decoded = JSON.parse current_power_response
puts "#{decoded['Payload']['CurrentProduction']}kW"
puts "#{decoded['Payload']['SystemList'][0]['DateTimeReceived']}"
