require_relative 'all_avatars_names'
require_relative 'hex_mini_test'
require_relative '../../src/runner_service'
require 'json'

class TestBase < HexMiniTest

  def self.multi_os_test(hex_suffix, *lines, &block)
    alpine_lines = ['[Alpine]'] + lines
    test(hex_suffix+'0', *alpine_lines, &block)
    ubuntu_lines = ['[Ubuntu]'] + lines
    test(hex_suffix+'1', *ubuntu_lines, &block)
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - -

  def runner
    RunnerService.new
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - -

  def kata_new(named_args = {})
    runner.kata_new(*common_args(named_args))
    nil
  end

  def kata_old(named_args={})
    runner.kata_old(*common_args(named_args))
    nil
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - -

  def avatar_new(named_args = {})
    args = common_args(named_args)
    args << defaulted_arg(named_args, :avatar_name,    avatar_name)
    args << defaulted_arg(named_args, :starting_files, starting_files)
    runner.avatar_new(*args)
    @avatar_name = args[-2]
    @all_files = args[-1]
    nil
  end

  def avatar_old(named_args = {})
    args = common_args(named_args)
    args << defaulted_arg(named_args, :avatar_name, avatar_name)
    runner.avatar_old(*args)
    nil
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - -

  def run_cyber_dojo_sh(named_args = {})

    unchanged_files = @all_files

    changed_files = defaulted_arg(named_args, :changed_files, {})
    changed_files.keys.each do |filename|
      diagnostic = "#{filename} is not a changed_file (it does not already exist)"
      assert unchanged_files.keys.include?(filename), diagnostic
      unchanged_files.delete(filename)
    end

    new_files = defaulted_arg(named_args, :new_files, {})
    new_files.keys.each do |filename|
      diagnostic = "#{filename} is not a new_file (it already exists)"
      refute unchanged_files.keys.include?(filename), diagnostic
    end

    args = common_args(named_args)
    args << defaulted_arg(named_args, :avatar_name, avatar_name)
    args << new_files
    args << defaulted_arg(named_args, :deleted_files, {})
    args << unchanged_files
    args << changed_files
    args << defaulted_arg(named_args, :max_seconds, 10)

    @json = runner.run_cyber_dojo_sh(*args)

    @all_files = [ *unchanged_files, *changed_files, *new_files ].to_h
    nil
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - -

  def json
    # If I change this to result/@result
    # then it clashes with result from http_json_service
    # which I do not understand as it does not look like
    # it is in scope?
    @json
  end

  def stdout
    json['stdout']
  end

  def stderr
    json['stderr']
  end

  def colour
    json['colour']
  end

  def new_files
    json['new_files']
  end

  def deleted_files
    json['deleted_files']
  end

  def changed_files
    json['changed_files']
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - -

  def red?
    colour == 'red'
  end

  def amber?
    colour == 'amber'
  end

  def green?
    colour == 'green'
  end

  def timed_out?
    colour == 'timed_out'
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - -

  def assert_cyber_dojo_sh(sh_script)
    run_cyber_dojo_sh({
      changed_files: { 'cyber-dojo.sh' => sh_script }
    })
    refute timed_out?, json
    assert_equal '', stderr
    stdout.strip
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - -

  def image_name
    @image_name || manifest['image_name']
  end

  INVALID_IMAGE_NAME = '_cantStartWithSeparator'
    VALID_IMAGE_NAME = 'cyberdojofoundation/gcc_assert'

    # - - - - - - - - - - - - - - - - - - - - - - - - - -

  def kata_id
    hex_test_id + '0' * (10 - hex_test_id.length)
  end

  INVALID_KATA_ID = '675'

  # - - - - - - - - - - - - - - - - - - - - - - - - - -

  include AllAvatarsNames

  def avatar_name
    @avatar_name || salmon
  end

  def salmon
    'salmon'
  end

  INVALID_AVATAR_NAME = 'sunglasses'

  # - - - - - - - - - - - - - - - - - - - - - - - - - -

  def user_id
    40000 + all_avatars_names.index(avatar_name)
  end

  def group_id
    5000
  end

  def group
    'cyber-dojo'
  end

  def home_dir
    "/home/#{avatar_name}"
  end

  def sandbox_dir
    "/sandboxes/#{avatar_name}"
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - -

  def starting_files
    Hash[manifest['visible_filenames'].collect { |filename|
      [filename, IO.read("#{starting_files_dir}/#{filename}")]
    }]
  end

  def manifest
    @manifest ||= JSON.parse(IO.read("#{starting_files_dir}/manifest.json"))
  end

  def starting_files_dir
    "/app/test/start_files/#{os}"
  end

  def os
    if hex_test_name.start_with? '[C,assert]'
      return :C_assert
    elsif hex_test_name.start_with? '[Ubuntu]'
      return :Ubuntu
    else # [Alpine] || default
      :Alpine
    end
  end

  private # = = = = = = = = = = = =

  def common_args(named_args)
    args = []
    args << defaulted_arg(named_args, :image_name, image_name)
    args << defaulted_arg(named_args, :kata_id,    kata_id)
    args
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - -

  def defaulted_arg(named_args, arg_name, arg_default)
    named_args.key?(arg_name) ? named_args[arg_name] : arg_default
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - -

  def in_kata_as(name)
    in_kata {
      as(name) {
        yield
      }
    }
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - -

  def in_kata
    kata_new
    begin
      yield
    ensure
      kata_old
    end
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - -

  def as(name, files = starting_files)
    avatar_new({ avatar_name: name, starting_files: files })
    begin
      yield
    ensure
      avatar_old({ avatar_name: name })
    end
  end

end
