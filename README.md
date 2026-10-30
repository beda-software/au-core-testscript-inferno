# AU Core TestScript Test Kit

An [Inferno](https://github.com/inferno-community/inferno-core) Test Kit that runs the AU Core
[FHIR TestScripts](https://hl7.org/fhir/R4/testscript.html) in `resources/` against a FHIR server.
The scripts are executed by [testscript_eval](https://github.com/beda-software/testscript-eval-ruby),
which is included as a git submodule.

## How TestScripts map to Inferno

Every TestScript in `resources/` becomes an Inferno test group; nothing is written by hand per script:

| Inferno                 | TestScript                                                                 |
|-------------------------|----------------------------------------------------------------------------|
| Group                   | One TestScript (`title`, `description`)                                    |
| **Setup** test          | Loads and autocreates `fixture`s, resolves `variable`s, runs `setup`        |
| One test per `test`     | The test's actions; a failed assert fails the test, `warningOnly` ones add warnings |
| **Teardown** test       | Runs `teardown` and autodeletes the fixtures, also after failures          |

- A group always runs as a whole (`run_as_group`), as its tests share the fixtures created on the server.
  When Setup fails, the group's tests are skipped and Teardown still cleans up.
- Requests go through Inferno's FHIR client, so every request is listed on the test that made it.
- `validateProfileId` asserts use Inferno's FHIR resource validator (AU Core 2.0.0); validation
  messages are shown on the test.
- Other resources in `resources/` (e.g. `au-core-patient-conformant.json`) are fixtures, referenced
  from the scripts as `file://<name>.json`. To add a script, drop a TestScript JSON file in `resources/`.

### Code

- `lib/inferno_template/test_script_group.rb`: `InfernoTemplate::TestScriptGroup`, the component
  that turns TestScript files into groups. Extend a suite or group with it and call
  `testscript_groups(glob)` (one group per TestScript among the matching files) or
  `testscript_group(definition, root_dir:)`.
- `lib/inferno_template/test_script_suite.rb`: the `AU Core TestScript` suite (id `inferno_template`),
  with the `url` and `authorization` inputs, the FHIR client and the validator.
- `testscript-eval-ruby/`: the testscript_eval submodule. The kit uses its step-by-step API
  (`Evaluator#start`, `#run_test`, `#finish`), and plugs in its own client
  (`TestscriptEval::Client.new(fhir_client) { |reply| ... }`) and validator.

## Inputs and presets

- **FHIR Server Base Url** (`url`)
- **Authorization header** (`authorization`, optional): sent as is, e.g. `Basic cm9vdDpzZWNyZXQ=`

Presets in `config/presets/` for a local Aidbox with `root:secret`:

| Preset                             | Use when Inferno runs        | Base URL                                |
|------------------------------------|------------------------------|-----------------------------------------|
| Local Aidbox                       | on the host (`inferno start`) | `http://localhost:8080/fhir`            |
| Local Aidbox (Inferno in Docker)   | in Docker (`./run.sh`)        | `http://host.docker.internal:8080/fhir` |

Inside Docker, `localhost` is the container itself, and `http://host.docker.internal/fhir` (no port)
reaches this kit's own nginx on port 80, which answers every request with 404. Keep the port of your
FHIR server in the URL. Inferno keeps a session's inputs, so after changing servers, update the URL in
the run dialog or start a new session from the preset.

## Getting Started

The quickest way to run this test kit locally is with [Docker](https://www.docker.com/).

- Install Docker
- Clone this repository with its submodule:
  `git clone --recurse-submodules <repo>`, or run `git submodule update --init` in an existing clone
- Run `./setup.sh` within the test kit directory to download necessary dependencies
- Run `./run.sh` within the test kit directory to start the application
- Navigate to `http://localhost`, create an `AU Core TestScript` session and pick a preset

From the command line, with the background services running (`bundle exec inferno services start`):

```sh
bundle exec inferno migrate
bundle exec inferno execute --suite inferno_template --preset-id local_aidbox
```

Presets in `config/presets/` are loaded automatically: select them with `--preset-id`, not `--preset-file`.

## Developing

Refer to the Inferno documentation for information about [setting up
your development environment and running your Test Kit](https://inferno-framework.github.io/docs/getting-started/).

### The testscript_eval submodule

The `testscript_eval` gem is loaded from the `testscript-eval-ruby/` submodule
(`gem 'testscript_eval', path: 'testscript-eval-ruby'`), which the Dockerfile copies into the image
before `bundle install`. The CI workflows check out submodules.

- To work on testscript_eval, commit and push in `testscript-eval-ruby/`, then commit the new submodule
  pointer here. Docker and CI clone the pinned commit from GitHub, so it has to be pushed.
- To update it: `git -C testscript-eval-ruby pull`, then commit the submodule pointer.
- `.gitmodules` uses HTTPS so CI and Docker can clone without SSH keys. To push over SSH locally:

  ```sh
  git config submodule.testscript-eval-ruby.url git@github.com:beda-software/testscript-eval-ruby.git
  git -C testscript-eval-ruby remote set-url origin git@github.com:beda-software/testscript-eval-ruby.git
  ```

  `git submodule sync` resets the URL to the HTTPS one from `.gitmodules`.

### Verifying test kit logic

- Unit tests (rspec) in `spec/`: `bundle exec rspec`. `spec/inferno_template/test_script_group_spec.rb`
  checks that every TestScript becomes a group and runs the AU Core Patient group against stubbed requests.
  testscript_eval has its own specs: `cd testscript-eval-ruby && bundle exec rspec`.
- Lint: `bundle exec rubocop` (the submodule is excluded).
- Both run in the ruby.yml workflow (`.github/workflows/ruby.yml`).
- Execution scripts: none are included; the template's demo script was removed. See
  [CI/CD Usage](https://inferno-framework.github.io/docs/ci-cd-usage.html) for adding them to
  `execution_scripts/`, where the run_inferno_execution_scripts.yml workflow picks them up.

## Documentation
- [Inferno documentation](https://inferno-framework.github.io/docs/)
- [Ruby API documentation](https://inferno-framework.github.io/inferno-core/docs/)
- [JSON API documentation](https://inferno-framework.github.io/inferno-core/api-docs/)
- [testscript_eval](https://github.com/beda-software/testscript-eval-ruby)

## License
Copyright 2026 TODO

Licensed under the Apache License, Version 2.0 (the "License"); you may not use
this file except in compliance with the License. You may obtain a copy of the
License at
```
http://www.apache.org/licenses/LICENSE-2.0
```
Unless required by applicable law or agreed to in writing, software distributed
under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
CONDITIONS OF ANY KIND, either express or implied. See the License for the
specific language governing permissions and limitations under the License.

## Trademark Notice

HL7, FHIR and the FHIR [FLAME DESIGN] are the registered trademarks of Health
Level Seven International and their use does not constitute endorsement by HL7.
