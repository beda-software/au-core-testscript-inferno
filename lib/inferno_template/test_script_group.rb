require 'testscript_eval'

module InfernoTemplate
  # Turns FHIR TestScript files into Inferno groups: one group per TestScript, with a Setup test
  # (fixtures, variables, setup actions), one test per TestScript test and a Teardown test.
  # Extend a suite or group with it, then call `testscript_group` or `testscript_groups`.
  #
  # The scripts run with testscript_eval, through the runnable's `fhir_client` and FHIR resource
  # validator, so requests and validation messages show up on each test.
  module TestScriptGroup
    # Defines a group for every TestScript among the files matching `glob`; other resources
    # (e.g. fixtures next to the scripts) are skipped
    def testscript_groups(glob)
      Dir[glob].each do |path|
        definition = TestscriptEval.load_file(path)
        testscript_group(definition, root_dir: File.dirname(path)) if definition['resourceType'] == 'TestScript'
      end
    end

    # Defines a group for a TestScript Hash; `root_dir` resolves its file:// fixture references
    def testscript_group(definition, root_dir:)
      group(definition['title'] || definition['name'],
            id: definition['id'].tr('-', '_'), description: definition['description']) do
        extend Steps

        # The tests share an evaluator and the fixtures it created on the server
        run_as_group

        testscript_step(:setup, 'Setup', 'Create the fixtures, resolve the variables and run the setup actions.') do
          start_testscript(definition, root_dir)
        end

        definition.fetch('test', []).each.with_index(1) do |test, index|
          testscript_step(:"test_#{index}", test['name'] || "Test #{index}", test['description']) do
            run_testscript_test(test)
          end
        end

        testscript_step(:teardown, 'Teardown', 'Run the teardown actions and delete the created fixtures.') do
          finish_testscript
        end
      end
    end

    # Group-level macro for the generated tests
    module Steps
      def testscript_step(id, title, description, &step)
        test(title, id:, description: description || title) do
          include Runner

          run(&step)
        end
      end
    end

    # What every generated test runs with. The group's evaluator lives in `scratch`, which all
    # tests of one run share
    module Runner
      def start_testscript(definition, root_dir)
        state = scratch[testscript_key] = { evaluator: TestscriptEval::Evaluator.new(definition, {}, root_dir:) }
        with_testscript(state[:evaluator], &:start)
        state[:ready] = true
      end

      def run_testscript_test(test)
        state = scratch[testscript_key]
        skip_if !state&.dig(:ready), 'Setup did not complete'

        with_testscript(state[:evaluator]) { |evaluator| evaluator.run_test(test) }
          .each { |message| warning message }
      end

      def finish_testscript
        state = scratch.delete(testscript_key)
        skip_if state.nil?, 'Setup did not run'

        with_testscript(state[:evaluator], &:finish)
      end

      private

      def testscript_key
        :"testscript_#{self.class.parent.id}"
      end

      # Binds the evaluator to this test's FHIR client and validator, and turns failed TestScript
      # asserts into failed tests; other TestscriptEval errors make the test an error
      def with_testscript(evaluator)
        evaluator.client = TestscriptEval::Client.new(fhir_client) { |reply| store_request('outgoing') { reply } }
        evaluator.validator = method(:testscript_validation_errors)
        yield evaluator
      rescue TestscriptEval::AssertionFailed => e
        raise Inferno::Exceptions::AssertionException, e.message
      end

      def testscript_validation_errors(resource, profile_url)
        return [] if resource_is_valid?(resource: FHIR.from_contents(resource.to_json), profile_url:)

        ["#{resource['resourceType']}/#{resource['id']} is not valid, see the messages for details"]
      end
    end
  end
end
