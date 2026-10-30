require_relative 'metadata'
require_relative 'test_script_group'

module InfernoTemplate
  RESOURCES_DIR = File.expand_path('../../resources', __dir__)

  class TestScriptSuite < Inferno::TestSuite
    extend TestScriptGroup

    id :inferno_template
    title 'AU Core TestScript'
    short_title 'AU Core TestScript'

    description <<~DESCRIPTION
      Runs the AU Core FHIR TestScripts against a FHIR server. Every TestScript is a test group:
      Setup creates its fixtures on the server, each TestScript test is an Inferno test, and
      Teardown deletes the fixtures again. A group runs as a whole, as its tests share the fixtures.
    DESCRIPTION

    input :url,
          title: 'FHIR Server Base Url'

    input :authorization,
          title: 'Authorization header',
          description: 'Sent as is in the Authorization header, e.g. `Basic cm9vdDpzZWNyZXQ=`',
          optional: true

    fhir_client do
      url :url
      headers({ 'Authorization' => authorization.presence }.compact)
    end

    fhir_resource_validator do
      igs 'hl7.fhir.au.core#2.0.0'

      exclude_message do |message|
        message.message.match?(/\A\S+: \S+: URL value '.*' does not resolve/)
      end
    end

    testscript_groups File.join(RESOURCES_DIR, '*.json')
  end
end
