require_relative './runner_test_base'

class DockerRunnerLanguageTest < RunnerTestBase

  def self.hex_prefix
    '9D930'
  end

  def hex_setup
    new_avatar
  end

  def hex_teardown
    old_avatar
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - -
  # TODO: add check that gcc_assert is Alpine-based
  # TODO: add check that Java,Cucumber is Ubuntu-based

  test 'CA0',
  '[C(gcc),assert] runs (an Alpine-based image)' do
    stdout, stderr = assert_run_completes(files('gcc_assert'))
    assert stderr.include?('Assertion failed: answer() == 42'), stderr
    assert_equal '', stdout
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - -

  test '5F0',
  '[Java,Cucumber] runs (an Ubuntu-based image)' do
    stdout, _ = assert_run_completes_no_stderr(files('java_cucumber'))
    assert stdout.include?('Hiker.feature:4 # Scenario: last earthling playing scrabble'), stdout
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - -

  test '182',
  '[C#-NUnit] runs (it needs to pick up HOME from the current user)' do
    stdout, _ = assert_run_completes_no_stderr(files('csharp_nunit'))
    assert stdout.include?('Tests run: 1, Errors: 0, Failures: 1, Inconclusive: 0'), stdout
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - -

  test 'C87',
  '[C#,Moq] runs (it explicitly names /sandbox in cyber-dojo.sh)' do
    stdout, _ = assert_run_completes_no_stderr(files('csharp_moq'))
    assert stdout.include?('Tests run: 1, Errors: 0, Failures: 1, Inconclusive: 0'), stdout
  end

end

