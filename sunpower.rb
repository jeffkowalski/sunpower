#!/usr/bin/env ruby

require 'net/http'
require 'uri'
require 'open-uri'
require 'json'
require 'yaml/store'


sunpower_credentials = YAML.load_file File.join(Dir.home, '.credentials', "sunpower.yaml")

uri = URI.parse("https://monitor.us.sunpower.com/CustomerPortal/Auth/Auth.svc/Authenticate")
http = Net::HTTP.new(uri.hostname, uri.port)
http.use_ssl = true
response = http.send_request('POST', uri.path, sunpower_credentials.to_json,
                             {'Content-Type' => 'application/json'})
puts response.body
decoded = JSON.parse response.body

content = open("https://monitor.us.sunpower.com/CustomerPortal/CurrentPower/CurrentPower.svc/GetCurrentPower?id=#{decoded['Payload']['TokenID']}").read
puts content
decoded = JSON.parse content
puts "#{decoded['Payload']['CurrentProduction']}kW"
puts "#{decoded['Payload']['SystemList'][0]['DateTimeReceived']}"
