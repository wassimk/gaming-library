require "test_helper"

class RunTest < Minitest::Test
  def test_run_file_has_valid_syntax
    result = `bundle exec ruby -c lib/run.rb 2>&1`
    assert_includes result, "Syntax OK", "lib/run.rb has a syntax error: #{result}"
  end
end
