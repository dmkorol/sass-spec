require 'pathname'
require 'yaml'
module SassSpec
  class TestCaseMetadata
    def self.cache
      @metadata_cache ||= {}
    end

    # If you change this, also change Annotate::CLI#annotate_path
    def self.merge_options(existing_opts, new_opts)
      existing_opts = existing_opts.dup

      new_opts.each do |key, value|
        if key =~ /add_(.*)/
          key = $1.to_sym
          existing_opts[key] ||= []
          value.each do |v|
            existing_opts[key] << v
          end
          existing_opts[key].uniq!
        elsif key =~ /remove_(.*)/
          key = $1.to_sym
          existing_opts[key] ||= []
          value.each do |v|
            existing_opts[key].delete(v)
          end
          existing_opts.delete(key) if existing_opts[key].empty?
        elsif value.nil?
          existing_opts.delete(key)
        else
          existing_opts[key] = value
        end
      end

      existing_opts
    end

    ACCUMULATED_OPTIONS = [:todo, :warning_todo, :ignore_for, :ignore_warning_for, :only_on, :warning_only_on]

    attr_reader :options

    def initialize(test_case_dir, spec_dir = SassSpec::SPEC_DIR)
      @test_case_dir = Pathname.new(File.expand_path(test_case_dir))
      @spec_dir = Pathname.new(spec_dir)
      if @test_case_dir.relative_path_from(@spec_dir).to_s.start_with?("..")
        raise ArgumentError,
          "Test case #{test_case_dir} is not within the spec directory #{spec_dir}"
      end
      @options = resolve_options(@test_case_dir).freeze
    end

    def name
      @test_case_dir.relative_path_from(Pathname.new(Dir.pwd)).to_s
    end

    def _resolve_options(dir)
      return {} if dir.relative_path_from(@spec_dir).to_s == "."
      parent_options = resolve_options(dir.parent)
      options_file = dir + "options.yml"
      self_options = if options_file.exist?
                       YAML.load_file(options_file.to_s)
                     else
                       {}
                     end
      rv = parent_options.merge(self_options) do |key, parent_value, self_value|
        if ACCUMULATED_OPTIONS.include?(key)
          (Array(parent_value) + Array(self_value)).uniq
        else
          self_value
        end
      end
      rv
    end

    def resolve_options(dir)
      self.class.cache[dir] ||= _resolve_options(dir).freeze
    end

    def todo?(impl)
      @options[:todo] && @options[:todo].include?(impl)
    end

    def warning_todo?(impl)
      @options[:warning_todo] && @options[:warning_todo].include?(impl)
    end

    def all_warning_todos
      @options[:warning_todo] || []
    end

    def ignore_for?(impl)
      (@options[:ignore_for] && @options[:ignore_for].include?(impl)) ||
        (@options[:only_on] && !@options[:only_on].include?(impl))
    end

    def ignore_warning_for?(impl)
      (@options[:ignore_warning_for] && @options[:ignore_warning_for].include?(impl)) ||
        (@options[:warning_only_on] && @options[:warning_only_on].include?(impl))
    end

    def warnings_ignored_for
      @options[:ignore_warning_for] || []
    end

    def output_style
      @options[:output_style]
    end

    def precision
      @options[:precision]
    end

    def clean_output?
      !!@options[:clean]
    end

    def start_version
      @start_version ||= Gem::Version.new(@options[:start_version] || SassSpec::MIN_LANGUAGE_VERSION)
    end

    def end_version
      unless defined?(@end_version)
        @end_version = if @options[:end_version]
                         Gem::Version.new(@options[:end_version])
                       else
                         nil
                       end
      end
      @end_version
    end

    def valid_for_version?(version)
      version = Gem::Version.new(version) if version.is_a?(String)
      valid = start_version <= version 
      if end_version
        valid &&= version <= end_version
      end
      valid
    end

    def valid_for_impl?(impl)
      !ignore_for?(impl)
    end

  end
end
