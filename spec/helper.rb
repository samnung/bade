require 'rspec'

require_relative '../lib/bade'



module Bade::Spec
  include Bade

  # Render source to html
  #
  # @param [String] expectation
  # @param [String] source
  #
  def assert_html(expectation, source, print_error_if_error: true)
    renderer = Bade::Renderer.from_source(source)

    begin
      str = renderer.render(new_line: '', indent: '')

      expect(str).to eq expectation

    rescue Exception
      if print_error_if_error
        puts renderer.lambda_string
      end

      raise
    end
  end

  def lambda_str_from_bade_code(source)
    parser = Bade::Parser.new
    parsed = parser.parse(source)
    Bade::RubyGenerator.document_to_lambda_string(parsed, indent: '')
  end
end
