require_relative '../test_helper'
require_relative '../../lib/exercism/language'

class LanguageTest < Minitest::Test
  def setup
    Language.instance_variable_set(:"@by_track_id", {"cpp" => "C++"})
  end

  def teardown
    Language.instance_variable_set(:"@by_track_id", nil)
  end

  def test_language_name
    assert_equal 'C++', Language.of('cpp')
    assert_equal 'C++', Language.of(:cpp)
    assert_equal 'C++', Language.of('CPP')
  end
end
