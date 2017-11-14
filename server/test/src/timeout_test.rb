require_relative 'test_base'

class TimeoutTest < TestBase

  def self.hex_prefix
    '45B57'
  end

  def hex_setup
    set_image_name image_for_test
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - -

  test 'B2B',
  %w( [gcc,assert]
      when run
        does not complete in max_seconds
          and
        does not produce output
      then
        the output is empty
          and
        the colour is timed_out
  ) do
    in_kata {
      as('salmon') {
        named_args = {
          changed_files: { 'hiker.c' => quiet_infinite_loop },
            max_seconds: 2
        }
        assert_run_times_out(named_args)
        assert_equal '', stdout
      }
    }
  end

  def quiet_infinite_loop
    [
      '#include "hiker.h"',
      'int answer(void)',
      '{',
      '    for(;;);',
      '    return 6 * 7;',
      '}'
    ].join("\n")
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - -

  test '4D7',
  %w( [gcc,assert]
      when run
        does not complete in max_seconds
          and
        does produce output
      then
        the output is not empty
          and
        the colour is timed_out
  ) do
    in_kata {
      as('salmon') {
        named_args = {
          changed_files: { 'hiker.c' => loud_infinite_loop },
            max_seconds: 2
        }
        assert_run_times_out(named_args)
        refute_equal '', stdout
      }
    }
  end

  def loud_infinite_loop
    [
      '#include "hiker.h"',
      '#include <stdio.h>',
      'int answer(void)',
      '{',
      '    for(;;)',
      '        puts("Hello");',
      '    return 6 * 7;',
      '}'
    ].join("\n")
  end

end


