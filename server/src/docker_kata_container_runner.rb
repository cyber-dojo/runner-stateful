require_relative 'all_avatars_names'
require_relative 'nearest_ancestors'
require_relative 'string_cleaner'
require_relative 'string_truncater'
require 'timeout'

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Uses one long-lived container per kata and then
# [docker exec]'ing a new process inside the
# kata's container for each avatar's run().
#
# Positives:
#   o) opens the way to avatars having shared state.
#   o) reduces run() execution time
#      eg on gcc_assert ~ 0.4s -> 0.3s.
#
# Negatives:
#   o) the cyber-dojo.sh process is not running as
#      pid-1. A pid-1 process is a robust way of
#      killing an entire process tree.
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

class DockerKataContainerRunner

  def initialize(parent)
    @parent = parent
    @logging = true
  end

  attr_reader :parent

  def logging_off; @logging = false; end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  # pull
  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def pulled?(image_name)
    image_names.include?(image_name)
  end

  def pull(image_name)
    assert_exec("docker pull #{image_name}")
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  # kata
  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def kata_exists?(_image_name, kata_id)
    assert_valid_id(kata_id)

    name = container_name(kata_id)
    cmd = "docker ps --quiet --all --filter name=#{name}"
    stdout,_ = assert_exec(cmd)
    stdout.strip != ''
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def new_kata(image_name, kata_id)
    refute_kata_exists(kata_id)

    name = container_name(kata_id)
    args = [
      '--detach',
      '--interactive',                     # later execs
      "--name=#{name}",
      '--net=none',                        # security
      '--pids-limit=256',                  # security
      '--security-opt=no-new-privileges',  # security
      '--user=root',
      "--volume #{sandboxes_root}",
    ].join(space)
    cmd = "docker run #{args} #{image_name} sh -c 'sleep 1d'"
    assert_exec(cmd)

    my_dir = File.expand_path(File.dirname(__FILE__))
    docker_cp = [
      'docker cp',
      "#{my_dir}/timeout_cyber_dojo.sh",
      "#{name}:/usr/local/bin"
    ].join(space)
    assert_exec(docker_cp)

    add_group = add_group_cmd(kata_id)
    assert_docker_exec(kata_id, add_group)

    # setup /etc/skel in Alpine
    if alpine? kata_id
      mkdir_etc_skel = 'mkdir -m 755 /etc/skel'
      assert_docker_exec(kata_id, mkdir_etc_skel)
    end
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def old_kata(image_name, kata_id)
    assert_kata_exists(kata_id)

    name = container_name(kata_id)
    cmd = "docker rm --force --volumes #{name}"
    assert_exec(cmd)
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  # avatar
  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def avatar_exists?(_image_name, kata_id, avatar_name)
    assert_kata_exists(kata_id)
    assert_valid_name(avatar_name)

    id_cmd = docker_cmd(kata_id, "id #{avatar_name}")
    _,_,status = exec(id_cmd, logging = false)
    status == success
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def new_avatar(_image_name, kata_id, avatar_name, starting_files)
    assert_kata_exists(kata_id)
    refute_avatar_exists(kata_id, avatar_name)

    add_user = add_user_cmd(kata_id, avatar_name)
    assert_docker_exec(kata_id, add_user)

    write_files(kata_id, avatar_name, starting_files)
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def old_avatar(_image_name, kata_id, avatar_name)
    assert_kata_exists(kata_id)
    assert_avatar_exists(kata_id, avatar_name)

    del_user = del_user_cmd(kata_id, avatar_name)
    assert_docker_exec(kata_id, del_user)
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  # run
  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def run(_image_name, kata_id, avatar_name, deleted_filenames, changed_files, max_seconds)
    assert_kata_exists(kata_id)
    assert_avatar_exists(kata_id, avatar_name)

    delete_files(kata_id, avatar_name, deleted_filenames)
    write_files(kata_id, avatar_name, changed_files)
    stdout,stderr,status = run_cyber_dojo_sh(kata_id, avatar_name, max_seconds)
    stdout = truncated(cleaned(stdout))
    stderr = truncated(cleaned(stderr))
    { stdout:stdout, stderr:stderr, status:status }
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  # properties
  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def user_id(avatar_name)
    assert_valid_name(avatar_name)
    40000 + all_avatars_names.index(avatar_name)
  end

  def group
    'cyber-dojo'
  end

  def sandbox_path(avatar_name)
    assert_valid_name(avatar_name)
    "#{sandboxes_root}/#{avatar_name}"
  end

  private # ==========================================================

  include StringCleaner
  include StringTruncater

  def delete_files(kata_id, avatar_name, filenames)
    sandbox = sandbox_path(avatar_name)
    filenames.each do |filename|
      rm = "rm #{sandbox}/#{filename}"
      assert_docker_exec(kata_id, rm)
    end
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def write_files(kata_id, avatar_name, files)
    Dir.mktmpdir('runner') do |tmp_dir|
      files.each do |filename, content|
        host_filename = tmp_dir + '/' + filename
        disk.write(host_filename, content)
      end
      uid = user_id(avatar_name)
      cid = container_name(kata_id)
      sandbox = sandbox_path(avatar_name)

=begin
      # Dropped tar-pipe as it is changing the permissions of the
      # avatar's sandboxes/lion (eg) directory....
      # Revisit? when sandboxes/lion is not home dir of avatar

      cmd = [
        'tar',                # Tar Pipe
          "--owner=#{uid}",   # force ownership
          "--group=#{group}", # force group
          '-cf',              # create a new archive
          '-',                # write archive to stdout
          '-C',               # change to...
          "#{tmp_dir}",       # ...this dir
          '.',                # ...and archive it
          '| docker exec',    # pipe stdout to docker
            "-i #{cid}",      # container
            'tar',            #
            '-xf',            # extract archive
            '-',              # read archive from stdin
            '-C',             # after changing to
            sandbox           # this dir
      ].join(space)
      assert_exec(cmd)
=end

      docker_cp = "docker cp #{tmp_dir}/. #{cid}:/#{sandbox}"
      assert_exec(docker_cp)
      files.keys.each do |filename|
        chown = "chown #{avatar_name}:#{group} #{sandbox}/#{filename}"
        assert_docker_exec(kata_id, chown)
      end
    end
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def run_cyber_dojo_sh(kata_id, avatar_name, max_seconds)
    cid = container_name(kata_id)
    cmd = [
      '/usr/local/bin/timeout_cyber_dojo.sh',
      kata_id,
      avatar_name,
      max_seconds
    ].join(space)

    exec = [
      'docker exec',
      '--user=root',
      '--interactive',
      cid,
      "sh #{cmd}"
    ].join(space)

    r_stdout, w_stdout = IO.pipe
    r_stderr, w_stderr = IO.pipe
    pid = Process.spawn(exec, pgroup:true, out:w_stdout, err:w_stderr)
    begin
      Timeout::timeout(max_seconds) do
        Process.waitpid(pid)
        status = $?.exitstatus
        w_stdout.close
        w_stderr.close
        stdout = r_stdout.read
        stderr = r_stderr.read
        [stdout, stderr, status]
      end
    rescue Timeout::Error
      # Kill the [docker exec] spawned process. This does _not_
      # kill the cyber-dojo.sh process inside the exec'd docker
      # container (remove_container() in run() does that).
      # See https://github.com/docker/docker/issues/9098
      Process.kill(-9, pid)
      Process.detach(pid)
      ['', '', 'timed_out']
    ensure
      w_stdout.close unless w_stdout.closed?
      w_stderr.close unless w_stderr.closed?
      r_stdout.close
      r_stderr.close
    end
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def add_group_cmd(kata_id)
    if alpine? kata_id
      return 'addgroup -g 5000 cyber-dojo'
    end
    if ubuntu? kata_id
      return 'addgroup --gid 5000 cyber-dojo'
    end
  end

  def add_user_cmd(kata_id, avatar_name)
    if alpine?(kata_id)
      return alpine_add_user_cmd(avatar_name)
    end
    if ubuntu?(kata_id)
      return ubuntu_add_user_cmd(avatar_name)
    end
  end

  def del_user_cmd(kata_id, avatar_name)
    if alpine? kata_id
      return "deluser --remove-home #{avatar_name}"
    end
    if ubuntu? kata_id
      return "userdel --remove #{avatar_name}"
    end
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def alpine_add_user_cmd(avatar_name)
    sandbox = sandbox_path(avatar_name)
    uid = user_id(avatar_name)
    [ 'adduser',
        '-D',                  # dont assign a password
        "-h #{sandbox}",       # home dir
        '-s /bin/sh',          # shell
        "-u #{uid}",
        "-G #{group}",
        '-k /etc/skel',
        avatar_name
    ].join(space)
  end

  def ubuntu_add_user_cmd(avatar_name)
    sandbox = sandbox_path(avatar_name)
    uid = user_id(avatar_name)
    [ 'adduser',
        '--disabled-password',
        "--home #{sandbox}",
        "--uid #{uid}",
        "--ingroup #{group}",
        '--gecos ""',          # don't ask for details
        avatar_name
    ].join(space)
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def refute_kata_exists(kata_id)
    assert_valid_id(kata_id)
    if kata_exists?(nil, kata_id)
      fail_kata_id('exists')
    end
  end

  def assert_kata_exists(kata_id)
    assert_valid_id(kata_id)
    unless kata_exists?(nil, kata_id)
      fail_kata_id('!exists')
    end
  end

  def assert_valid_id(kata_id)
    unless valid_id?(kata_id)
      fail_kata_id('invalid')
    end
  end

  def valid_id?(kata_id)
    kata_id.class.name == 'String' &&
      kata_id.length == 10 &&
        kata_id.chars.all? { |char| hex?(char) }
  end

  def hex?(char)
    '0123456789ABCDEF'.include?(char)
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def refute_avatar_exists(kata_id, avatar_name)
    assert_valid_name(avatar_name)
    if avatar_exists?(nil, kata_id, avatar_name)
      fail_avatar_name('exists')
    end
  end

  def assert_avatar_exists(kata_id, avatar_name)
    assert_valid_name(avatar_name)
    unless avatar_exists?(nil, kata_id, avatar_name)
      fail_avatar_name('!exists')
    end
  end

  def assert_valid_name(avatar_name)
    unless valid_avatar?(avatar_name)
      fail_avatar_name('invalid')
    end
  end

  include AllAvatarsNames
  def valid_avatar?(avatar_name)
    all_avatars_names.include?(avatar_name)
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def assert_docker_exec(kata_id, cmd)
    assert_exec(docker_cmd(kata_id, cmd))
  end

  def assert_exec(cmd)
    stdout,stderr,status = exec(cmd)
    unless status == success
      fail_command(cmd)
    end
    [stdout,stderr]
  end

  def exec(cmd, logging = @logging)
    shell.exec(cmd, logging)
  end

  def docker_cmd(kata_id, cmd)
    cid = container_name(kata_id)
    "docker exec #{cid} sh -c '#{cmd}'"
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def fail_kata_id(message)
    fail bad_argument("kata_id:#{message}")
  end

  def fail_avatar_name(message)
    fail bad_argument("avatar_name:#{message}")
  end

  def fail_command(message)
    fail bad_argument("command:#{message}")
  end

  def bad_argument(message)
    ArgumentError.new(message)
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def alpine?(kata_id)
    etc_issue(kata_id).include?('Alpine')
  end

  def ubuntu?(kata_id)
    etc_issue(kata_id).include?('Ubuntu')
  end

  def etc_issue(kata_id)
    stdout,_ = assert_docker_exec(kata_id, 'cat /etc/issue')
    stdout
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def image_names
    cmd = 'docker images --format "{{.Repository}}"'
    stdout,_ = assert_exec(cmd)
    names = stdout.split("\n")
    names.uniq - ['<none']
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def container_name(kata_id)
    [ 'cyber', 'dojo', kata_id ].join('_')
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def sandboxes_root; '/sandboxes'; end
  def success; shell.success; end
  def space; ' '; end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  include NearestAncestors
  def shell; nearest_ancestors(:shell); end
  def  disk; nearest_ancestors(:disk ); end

end
