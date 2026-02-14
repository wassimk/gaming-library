require "test_helper"

class RunTest < Minitest::Test
  def test_run_file_loads_without_error
    assert require_relative("../lib/run")
  end
end
