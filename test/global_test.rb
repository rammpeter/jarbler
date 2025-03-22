require 'minitest/autorun'
require 'test_helper'

class GlobalTest < Minitest::Test
  def setup
    super
  end

  def teardown
    super
  end

  # Check if all .rb files in the whole project have either only ASCII characters or "# encoding: utf-8" set
  def test_check_for_charset
    # Check if all .rb files in the whole project have either only ASCII characters or "# encoding: utf-8" set
    Dir.glob('**/*.rb').each do |file|
      next if file =~ /^vendor/
      next if File.read(file) =~ /# encoding: utf-8/
      line_number = 0
      File.foreach(file) do |line, index|
        line_number += 1
        next if line.ascii_only?
        charpos = 0
        line.each_char do |char|
          charpos += 1
          next if char.ascii_only?
          raise "File '#{file}' contains non-ASCII characters in line #{line_number} at position #{charpos}.\nPlease add '# encoding: utf-8' to the file or fix the following line content:\n#{line}"
        end
      end
    end
  end
end
