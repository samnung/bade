# frozen_string_literal: true

require_relative '../helper'

describe Bade::Renderer, 'import feature' do
  it 'supports importing another file' do
    base_path = File.expand_path('files/base.bade', File.dirname(__FILE__))
    output = Bade::Renderer.from_file(File.new(base_path, 'r'))
                           .render(new_line: '')

    expect(output).to eq '<div>ahoj</div>'
  end

  context 'importing ruby file' do
    it 'supports importing relatively with extension' do
      base_path = File.expand_path('files/base.bade', File.dirname(__FILE__))

      source = <<-BADE.strip_heredoc
        import "imported_rb.rb"
        = z
      BADE

      output = Bade::Renderer.from_source(source, base_path)
                             .render(new_line: '')

      expect(output).to eq 'imported_rb'
    end

    it 'supports importing relatively without extension' do
      base_path = File.expand_path('files/base.bade', File.dirname(__FILE__))

      source = <<-BADE.strip_heredoc
        import "imported_rb"
        = z
      BADE

      output = Bade::Renderer.from_source(source, base_path)
                             .render(new_line: '')

      expect(output).to eq 'imported_rb'
    end

    it 'pass correct __FILE__ variable to loaded ruby file' do
      base_path = File.expand_path('files/base.bade', File.dirname(__FILE__))

      source = <<-BADE.strip_heredoc
        import "imported_rb"
        = file_path
      BADE

      output = Bade::Renderer.from_source(source, base_path)
                             .render(new_line: '')

      expect(output).to eq File.expand_path('files/imported_rb.rb', File.dirname(__FILE__))
    end

    it 'raises error when referenced file name matches multiple files' do
      base_path = File.expand_path('files/base.bade', File.dirname(__FILE__))

      source = <<-BADE.strip_heredoc
        import "folder/import_in_folder"
      BADE

      expect do
        Bade::Renderer.from_source(source, base_path)
                      .render(new_line: '')
      end.to raise_error(Bade::Renderer::LoadError, 'Found both .bade and .rb files for `folder/import_in_folder` in '\
                                                    'file base.bade, change the import path so it references uniq file.')
    end
  end
end
