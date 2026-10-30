RSpec.describe InfernoTemplate::TestScriptGroup do
  let(:suite_id) { 'inferno_template' }
  let(:suite) { Inferno::Repositories::TestSuites.new.find(suite_id) }
  let(:session_data_repo) { Inferno::Repositories::SessionData.new }
  let(:results_repo) { Inferno::Repositories::Results.new }
  let(:requests_repo) { Inferno::Repositories::Requests.new }
  let(:test_session) { repo_create(:test_session, test_suite_id: suite_id) }
  let(:validation_url) { "#{ENV.fetch('FHIR_RESOURCE_VALIDATOR_URL')}/validate" }

  let(:url) { 'http://example.com/fhir' }
  let(:authorization) { 'Basic cm9vdDpzZWNyZXQ=' }
  let(:json) { { 'Content-Type' => 'application/fhir+json' } }

  def run(runnable, inputs)
    test_run = Inferno::Repositories::TestRuns.new.create(
      { test_session_id: test_session.id }.merge(runnable.reference_hash)
    )
    inputs.each do |name, value|
      session_data_repo.save(test_session_id: test_session.id, name:, value:, type: 'text')
    end
    Inferno::TestRunner.new(test_session:, test_run:).run(runnable)
  end

  def resource(name)
    JSON.parse(File.read(File.join(InfernoTemplate::RESOURCES_DIR, "#{name}.json")))
  end

  def results(group)
    results_repo.current_results_for_test_session_and_runnables(test_session.id, group.tests)
      .to_h { |result| [result.runnable.title, result] }
  end

  def validator_outcome(issues = [])
    { outcomes: [{ issues: }], sessionId: test_session.id }.to_json
  end

  describe '.testscript_groups' do
    let(:scripts) do
      Dir[File.join(InfernoTemplate::RESOURCES_DIR, '*.json')]
        .map { |path| JSON.parse(File.read(path)) }
        .select { |definition| definition['resourceType'] == 'TestScript' }
    end

    it 'defines a group per TestScript, with Setup, a test per TestScript test and Teardown' do
      expect(suite.groups.map(&:title)).to match_array(scripts.map { |script| script['title'] })

      scripts.each do |script|
        group = suite.groups.find { |g| g.id == "#{suite_id}-#{script['id'].tr('-', '_')}" }
        expect(group).to be_run_as_group
        expect(group.tests.map(&:title)).to eq(['Setup', *script['test'].map { |test| test['name'] }, 'Teardown'])
      end
    end
  end

  describe 'running the AU Core Patient group' do
    let(:group) { suite.groups.find { |g| g.id.end_with?('-au_core_patient') } }
    let(:patient) { resource('au-core-patient-conformant') }
    let(:patient_url) { "#{url}/Patient/#{patient['id']}" }
    let(:bundle) { { resourceType: 'Bundle', type: 'searchset', entry: [{ resource: patient }] } }

    before do
      stub_request(:put, patient_url).to_return(status: 201, body: patient.to_json, headers: json)
      stub_request(:get, patient_url).to_return(status: 200, body: patient.to_json, headers: json)
      stub_request(:get, "#{url}/Patient").with(query: hash_including({}))
        .to_return(status: 200, body: bundle.to_json, headers: json)
      stub_request(:delete, patient_url).to_return(status: 204)
      stub_request(:post, validation_url).to_return(status: 200, body: validator_outcome)
    end

    it 'passes every test and records its requests' do
      run(group, url:, authorization:)

      expect(results(group).transform_values { |result| [result.result, result.result_message] })
        .to all(satisfy { |_title, (result, _message)| result == 'pass' })
      expect(a_request(:get, patient_url).with(headers: { 'Authorization' => authorization }))
        .to have_been_made.times(3)
      expect(a_request(:delete, patient_url)).to have_been_made.once

      requests = results(group).transform_values { |result| requests_repo.requests_for_result(result.id) }
      expect(requests['Setup'].map(&:verb)).to eq(['put'])
      expect(requests['SearchById'].map(&:url)).to eq(["#{url}/Patient?_id=#{patient['id']}"])
      expect(requests['Teardown'].map(&:verb)).to eq(['delete'])
    end

    it 'fails only the test whose assert fails, and still deletes the fixtures' do
      other = patient.merge('name' => [{ 'family' => 'Smith' }])
      stub_request(:get, "#{url}/Patient").with(query: { '_id' => patient['id'] })
        .to_return(status: 200, body: bundle.merge(entry: [{ resource: other }]).to_json, headers: json)

      run(group, url:, authorization:)

      expect(results(group).reject { |_title, result| result.result == 'pass' }.transform_values(&:result))
        .to eq('SearchById' => 'fail')
      expect(results(group)['SearchById'].result_message)
        .to include("Check: Bundle.entry.resource.ofType(Patient).name.family.contains('Frog')")
      expect(a_request(:delete, patient_url)).to have_been_made.once
    end

    it 'fails profile validation with the validator messages' do
      stub_request(:post, validation_url).to_return(
        status: 200,
        body: validator_outcome([{ location: 'Patient.gender', message: 'bad gender', level: 'ERROR' }])
      )

      run(group, url:, authorization:)

      result = results(group)['ProfileValidation']
      expect(result.result).to eq('fail')
      expect(result.result_message).to include('au-core-patient')
      expect(result.messages.map(&:message)).to include(/bad gender/)
    end

    it 'skips the tests when Setup fails' do
      stub_request(:put, patient_url).to_return(status: 500, body: 'boom')

      run(group, url:, authorization:)

      expect(results(group).transform_values(&:result))
        .to include('Setup' => 'error', 'Read' => 'skip', 'Teardown' => 'pass')
    end
  end
end
