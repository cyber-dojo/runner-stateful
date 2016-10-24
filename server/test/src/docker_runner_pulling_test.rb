
require_relative './lib_test_base'

class DockerRunnerPullingTest < LibTestBase

  def self.hex
    'CFC'
  end

  def external_setup
    ENV[env_name('log')] = 'NullLogger'
    assert_equal 'NullLogger', log.class.name
    assert_equal 'ExternalSheller', shell.class.name
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - -

  test 'A71',
  'pulled?(image_name) is false when image_name has not yet been pulled' do
    _output, status = runner.pulled?('thisdoes/not_exist')
    refute status
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - -

  test 'A4E',
  'pulled?(image_name) is true when image_name has already been pulled' do
    # use image-name of runner itself
    _output, status = runner.pulled?('cyberdojo/runner')
    assert status
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - -

  test 'DA5',
  'after pull(image_name) pulled(image_name) is true' do
    # something small not used in cyber-dojo
    image_name = 'busybox'
    _output, status = runner.pulled?(image_name)
    refute status

    runner.pull(image_name)

    _output, status = runner.pulled?(image_name)
    assert status

    output, status = shell.exec("docker rmi #{image_name}")
    fail "exited(#{status}):#{output}:" unless status == success
  end

  private

  def runner; DockerRunner.new(self); end
  def success; 0; end

  include Externals # for shell
  def exec(command); shell.exec(command); end

end
