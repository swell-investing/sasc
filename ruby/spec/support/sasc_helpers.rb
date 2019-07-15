#.## SASCHelpers
#. These are methods that help with writing tests for SASC controllers.
module SASCHelpers
  REQUEST_HEADERS = {
    "accept" => "application/json",
    "x-sasc" => "1.0.0",
    "x-sasc-api-version" => SASC::Versioning.latest_version.to_s,
    "x-sasc-client" => "swell-web 1.0.0 2147483647",
  }.freeze

  def sasc_request_headers(api_version = nil)
    headers = REQUEST_HEADERS.dup
    headers["x-sasc-api-version"] = api_version if api_version.present?
    headers
  end

  #% set_sasc_request_headers
  #. Set up the necessary headers in `request.headers` for a SASC request
  #.
  #. ```ruby
  #. RSpec.describe DogsController, type: :controller do
  #.   before do
  #.     set_sasc_request_headers
  #.   end
  #. end
  #. ```
  # rubocop:disable Style/AccessorMethodName
  def set_sasc_request_headers(api_version = nil)
    sasc_request_headers(api_version).each { |header, value| request.headers[header] = value }
  end

  #% be_sasc_error
  #. An RSpec matcher checking for SASC errors with the given fields in responses
  #.
  #. ```ruby
  #. RSpec.describe DogsController, type: :controller do
  #.   # ...
  #.
  #.   it 'fails with an invalid field value' do
  #.     subject
  #.     expect(response).to be_bad_request
  #.     expect(json).to be_sasc_error(code: '__INVALID_FIELD_VALUE__');
  #.   end
  #. end
  #. ```
  RSpec::Matchers.define :be_sasc_error do |expected|
    match do |actual|
      # We are expected errors to be an array of one object containing the expected k/v pairs
      expect(actual.dig(:errors, 0)).to include(expected)
    end
  end
end
