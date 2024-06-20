#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
Bundler.require(:default)

class Sunpower < RecorderBotBase
  no_commands do
    def authorize
      sunpower_credentials = load_credentials

      response = RestClient.post 'https://edp-api.edp.sunpower.com/v1/auth/okta/signin',
                                 sunpower_credentials.to_json,
                                 {
                                   Content_Type: 'application/json; charset=utf-8',
                                 }

      authorization = JSON.parse response
      @logger.debug authorization
      authorization
    end

    def get_current_power(authorization)
      sunpower_credentials = load_credentials

      change_query = [{
                        operationName: "FetchCurrentPower",
                        variables: { siteKey: sunpower_credentials['siteKey'] },
                        query: "query FetchCurrentPower($siteKey: String!) {currentPower(siteKey: $siteKey) { production, timestamp }}"
                      }].to_json

      response = RestClient.post 'https://edp-api-graphql.edp.sunpower.com/graphql',
                                 change_query,
                                 {
                                   Authorization: "Bearer #{authorization['access_token']}",
                                   Content_Type: 'application/json; charset=utf-8'
                                 }

      @logger.debug response.headers
      @logger.info response
      parsed_response = JSON.parse(response.body)
      return parsed_response[0]['data']['currentPower']
    end
  end

  no_commands do
    def main
      power = with_rescue([Errno::ECONNRESET], @logger, retries: 6) do |_try|
        authorization = authorize
        get_current_power authorization
      end

      influxdb = InfluxDB::Client.new 'sunpower' unless options[:dry_run]
      data = [{ series: 'production',
                values: { value: power['production'].to_f },
                timestamp: power['timestamp']/1000 }]  # convert ms to sec
      influxdb.write_points(data) unless options[:dry_run]
    end
  end
end

Sunpower.start
