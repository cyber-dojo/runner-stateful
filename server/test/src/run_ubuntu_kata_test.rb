require_relative 'test_base'
require_relative 'os_helper'

class RunUbuntuKataTest < TestBase

  include OsHelper

  def self.hex_prefix; '2C3B9'; end

  def hex_setup
    set_image_name image_for_test
    new_kata
  end

  def hex_teardown
    old_kata
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - -

  test 'CA1',
  '[Ubuntu] image is indeed based on Ubuntu' do
    etc_issue = assert_docker_exec 'cat /etc/issue'
    assert etc_issue.include?('Ubuntu'), etc_issue
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - -

  test '268',
  "[Ubuntu] none of the 64 avatar's uid's are already taken" do
    refute_avatar_users_exist
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - -

  test '583',
  '[Ubuntu] has group used for dir/file ownership' do
    assert_group_exists
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - -

  test '3B2',
  '[Ubuntu] after new_kata the timeout script is in /usr/local/bin' do
    src = assert_docker_exec('cat /usr/local/bin/timeout_cyber_dojo.sh')
    lines = src.split("\n")
    assert_equal '#!/usr/bin/env sh', lines[0]
    assert_equal '', lines[2]
    assert_equal 'KATA_ID=$1', lines[3]
    assert_equal 'AVATAR=$2', lines[4]
    assert_equal 'MAX_SECONDS=$3', lines[5]
  end

end
