
require_relative 'node'


module RJade
	class Parser
		class SyntaxError < StandardError
			attr_reader :error, :file, :line, :lineno, :column

			def initialize(error, file, line, lineno, column)
				@error = error
				@file = file || '(__TEMPLATE__)'
				@line = line.to_s
				@lineno = lineno
				@column = column
			end

			def to_s
				line = @line.lstrip
				column = @column + line.size - @line.size
				%{#{error}
	#{file}, Line #{lineno}, Column #{@column}
	#{line}
	#{' ' * column}^
}
			end
		end

		def initialize(options = {})
			@options = options

			# we support only tabs now
			@tab_re = "\t"
			@tab = ' '



			reset
		end

		# @param [String] str
		# @return [Node] root node
		#
		def parse(str)
			@root = Node.new(:root)

			reset(str.split(/\r?\n/), [[@root]])

			parse_line while next_line

			reset

			@root
		end



		private

		WORD_RE = ''.respond_to?(:encoding) ? '\p{Word}' : '\w'
		ATTR_NAME = "\\A\\s*(#{WORD_RE}(?:#{WORD_RE}|:|-)*)"
		QUOTED_ATTR_RE = /#{ATTR_NAME}\s*=(=?)\s*("|')/
		CODE_ATTR_RE = /#{ATTR_NAME}\s*=(=?)\s*/

		TAG_RE = /\A([a-zA-Z0-9]+)/

		def reset(lines = nil, stacks = nil)
			# Since you can indent however you like in Slim, we need to keep a list
			# of how deeply indented you are. For instance, in a template like this:
			#
			#   doctype       # 0 spaces
			#   html          # 0 spaces
			#    head         # 1 space
			#       title     # 4 spaces
			#
			# indents will then contain [0, 1, 4] (when it's processing the last line.)
			#
			# We uses this information to figure out how many steps we must "jump"
			# out when we see an de-indented line.
			@indents = [0]

			# Whenever we want to output something, we'll *always* output it to the
			# last stack in this array. So when there's a line that expects
			# indentation, we simply push a new stack onto this array. When it
			# processes the next line, the content will then be outputted into that
			# stack.
			@stacks = stacks

			@lineno = 0
			@lines = lines
			@line = @orig_line = nil
		end

		def next_line
			if @lines.empty?
				@orig_line = @line = nil
			else
				@orig_line = @lines.shift
				@lineno += 1
				@line = @orig_line.dup
			end
		end

		# Calculate indent for line
		#
		# @param [String] line
		# @return [Int] indent size
		#
		def get_indent(line)
			# Figure out the indentation. Kinda ugly/slow way to support tabs,
			# but remember that this is only done at parsing time.
			line[/\A[ \t]*/].gsub(@tab_re, @tab).size
		end

		# Append element to stacks and result tree
		#
		# @param [Symbol] type
		#
		def append_node(type, indent: @indents.last, add: false)
			parent = @stacks[indent].last
			node = Node.new(type, parent)
			node.lineno = @lineno

			if add
				@stacks[indent] << node
			end

			node
		end

		def parse_line
			line = @line

			if line =~ /\A\s*\Z/
				append_node :newline
				return
			end

			indent = get_indent(line)

			# left strip, similar to String#lstrip
			@line = line[indent ... line.length]

			# If there's more stacks than indents, it means that the previous
			# line is expecting this line to be indented.
			expecting_indentation = @stacks.length > @indents.length

			if indent > @indents.last
				@indents << indent
				@stacks << @stacks.last
			else
				# This line was *not* indented more than the line before,
				# so we'll just forget about the stack that the previous line pushed.
				@stacks.pop if expecting_indentation

				if indent < @indents.last
					while 1 < @stacks[indent].length
						@stacks[indent].pop
					end
				end

				# This line was deindented.
				# Now we're have to go through the all the indents and figure out
				# how many levels we've deindented.
				while indent < @indents.last
					@indents.pop
					@stacks.pop
				end

				# This line's indentation happens lie "between" two other line's
				# indentation:
				#
				#   hello
				#       world
				#     this      # <- This should not be possible!
				syntax_error('Malformed indentation') if indent != @indents.last
			end

			parse_line_indicators
		end

		def parse_line_indicators
			case @line

				when /\A\/!( ?)/
					# HTML comment
					@stacks.last << [:html, :comment, [:slim, :data, parse_text_block($', @indents.last + $1.size + 2)]]

				when /\A\/\[\s*(.*?)\s*\]\s*\Z/
					# HTML conditional comment
					block = [:multi]
					@stacks.last << [:html, :condcomment, $1, block]
					@stacks << block

				when /\A\//
					# Slim comment
					parse_comment_block

				when /\A([\|'])( ?)/
					# Found a text block.
					trailing_ws = $1 == "'"
					@stacks.last << [:slim, :data, parse_text_block($', @indents.last + $2.size + 1)]
					@stacks.last << [:static, ' '] if trailing_ws

				when /\A</
					# Inline html
					block = [:multi]
					@stacks.last << [:multi, [:slim, :interpolate, @line], block]
					@stacks << block

				when /\A-/
					# Found a code block.
					# We expect the line to be broken or the next line to be indented.
					@line.slice!(0)
					block = [:multi]
					@stacks.last << [:slim, :control, parse_broken_line, block]
					@stacks << block

				when /\A=(=?)(['<>]*)/
					# Found an output block.
					# We expect the line to be broken or the next line to be indented.
					@line = $'
					trailing_ws = $2.include?('\'') || $2.include?('>')
					block = [:multi]
					@stacks.last << [:static, ' '] if $2.include?('<')
					@stacks.last << [:slim, :output, $1.empty?, parse_broken_line, block]
					@stacks.last << [:static, ' '] if trailing_ws
					@stacks << block

				when /\A(\w+):\s*\Z/
					# Embedded template detected. It is treated as block.
					@stacks.last << [:slim, :embedded, $1, parse_text_block]

				when /\Adoctype\s+/i
					# Found doctype declaration
					@stacks.last << [:html, :doctype, $'.strip]

				when TAG_RE
					# Found a HTML tag.
					@line = $' if $1
					parse_tag($&)

				when /\A\|\s(.*)\Z/
					# piped text
					node = append_node :data
					node.data = $1

				else
					syntax_error 'Unknown line indicator'
			end

			append_node :newline
		end

		def parse_tag(tag)
			tag_node = append_node :tag, add: true
			tag_node.data = tag

			case @line
				when /\A\s*:\s*/
					# Block expansion
					@line = $'
					(@line =~ TAG_RE) || syntax_error('Expected tag')
					@line = $' if $1
					content = [:multi]
					tag << content
					i = @stacks.size
					@stacks << content
					parse_tag($&)
					@stacks.delete_at(i)

				when /\A\s*=(=?)/
					# Handle output code
					@line = $'
					block = [:multi]
					tag << [:slim, :output, $1 != '=', parse_broken_line, block]
					@stacks << block

				when /\A\s*\/\s*/
					# Closed tag. Do nothing
					@line = $'
					syntax_error('Unexpected text after closed tag') unless @line.empty?

				when /\A\s*\Z/
					# Empty content
					content = [:multi]
					tag << content
					@stacks << content

				when /\A( ?)(.*)\Z/
					# Text content
					text = append_node :data
					text.data = $2

			end
		end

		def parse_attributes(attributes)
			# Check to see if there is a delimiter right after the tag name
			delimiter = nil
			if @line =~ @attr_delim_re
				delimiter = options[:attr_delims][$1]
				@line = $'
			end

			if delimiter
				boolean_attr_re = /#{ATTR_NAME}(?=(\s|#{Regexp.escape delimiter}|\Z))/
				end_re = /\A\s*#{Regexp.escape delimiter}/
			end

			while true
				case @line
					when /\A\s*\*(?=[^\s]+)/
						# Splat attribute
						@line = $'
						attributes << [:slim, :splat, parse_ruby_code(delimiter)]
					when QUOTED_ATTR_RE
						# Value is quoted (static)
						@line = $'
						attributes << [:html, :attr, $1,
									   [:escape, $2.empty?, [:slim, :interpolate, parse_quoted_attribute($3)]]]
					when CODE_ATTR_RE
						# Value is ruby code
						@line = $'
						name = $1
						escape = $2.empty?
						value = parse_ruby_code(delimiter)
						syntax_error!('Invalid empty attribute') if value.empty?
						attributes << [:html, :attr, name, [:slim, :attrvalue, escape, value]]
					else
						break unless delimiter

						case @line
							when boolean_attr_re
								# Boolean attribute
								@line = $'
								attributes << [:html, :attr, $1, [:multi]]
							when end_re
								# Find ending delimiter
								@line = $'
								break
							else
								# Found something where an attribute should be
								@line.lstrip!
								syntax_error!('Expected attribute') unless @line.empty?

								# Attributes span multiple lines
								@stacks.last << [:newline]
								syntax_error!("Expected closing delimiter #{delimiter}") if @lines.empty?
								next_line
						end
				end
			end
		end


		def parse_text_block(first_line = nil, text_indent = nil)
			result = [:multi]
			if !first_line || first_line.empty?
				text_indent = nil
			else
				result << [:slim, :interpolate, first_line]
			end

			empty_lines = 0
			until @lines.empty?
				if @lines.first =~ /\A\s*\Z/
					next_line
					result << [:newline]
					empty_lines += 1 if text_indent
				else
					indent = get_indent(@lines.first)
					break if indent <= @indents.last

					if empty_lines > 0
						result << ([:newline] * empty_lines)
						empty_lines = 0
					end

					next_line
					@line.lstrip!

					# The text block lines must be at least indented
					# as deep as the first line.
					offset = text_indent ? indent - text_indent : 0
					if offset < 0
						syntax_error("Text line not indented deep enough.\n" +
										 'The first text line defines the necessary text indentation.')
					end

					result << [:newline] << [:slim, :interpolate, (text_indent ? "\n" : '') + (' ' * offset) + @line]

					# The indentation of first line of the text block
					# determines the text base indentation.
					text_indent ||= indent
				end
			end
			result
		end



		# ----------- Errors ---------------

		# Raise specific error
		#
		# @param [String] message
		#
		def syntax_error(message)
			raise SyntaxError.new(message, @options[:file], @orig_line, @lineno,
								  @orig_line && @line ? @orig_line.size - @line.size : 0)
		end
	end
end