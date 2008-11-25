class QuickSandbox
  include ActionView::Helpers::ActiveRecordHelper

  attr_accessor :form_action, :singular_name, :suffix, :model_instance

  def sandbox_binding
    binding
  end

  def default_input_block
    Proc.new { |record, column| "<p>#{input(record, column.name)}</p>\n" }
  end
end

class ActionView::Helpers::InstanceTag
  def to_label_tag(text = nil, options = {})
  end

  def to_input_field_tag(field_type, options={})
    "<!-- generic input -->\n<%= f.field :#{@method_name} #{options.empty? ? '' : ', '+options.inspect} %>"
    # field_meth = "#{field_type}_field"
    # "<%= #{field_meth} '#{@object_name}', '#{@method_name}' #{options.empty? ? '' : ', '+options.inspect} %>"
  end

  def to_text_area_tag(options = {})
    "<!-- text area -->\n<%= f.field :#{@method_name} #{options.empty? ? '' : ', '+options.inspect} %>"
    # "<%= text_area '#{@object_name}', '#{@method_name}' #{options.empty? ? '' : ', '+ options.inspect} %>"
  end

  def to_date_select_tag(options = {})
    "<!-- date select -->\n<%= f.field :#{@method_name} #{options.empty? ? '' : ', '+options.inspect} %>"
    # "<%= date_select '#{@object_name}', '#{@method_name}' #{options.empty? ? '' : ', '+ options.inspect} %>"
  end

  def to_time_select_tag(options = {})
    "<!-- time select -->\n<%= f.field :#{@method_name} #{options.empty? ? '' : ', '+options.inspect} %>"
    # "<%= time_select '#{@object_name}', '#{@method_name}' #{options.empty? ? '' : ', '+ options.inspect} %>"
  end

  def to_datetime_select_tag(options = {})
    "<!-- datetime select -->\n<%= f.field :#{@method_name} #{options.empty? ? '' : ', '+options.inspect} %>"
    # "<%= datetime_select '#{@object_name}', '#{@method_name}' #{options.empty? ? '' : ', '+ options.inspect} %>"
  end

  def to_radio_button_tag(tag_value, options = {})
    "<!-- radio button -->\n<%= f.field :#{@method_name} #{options.empty? ? '' : ', '+options.inspect} %>"
  end

  def to_check_box_tag(options = {}, checked_value = "1", unchecked_value = "0")
    "<!-- check box -->\n<%= f.field :#{@method_name} #{options.empty? ? '' : ', '+options.inspect} %>"
  end

  def to_boolean_select_tag(options = {})
    "<!-- boolean select -->\n<%= f.field :#{@method_name} #{options.empty? ? '' : ', '+options.inspect} %>"
  end

  
end


class QuickGenerator < Rails::Generator::NamedBase
  default_options :skip_timestamps => false, :skip_migration => false, :force_plural => false

  attr_reader   :controller_name,
                :controller_class_path,
                :controller_file_path,
                :controller_class_nesting,
                :controller_class_nesting_depth,
                :controller_class_name,
                :controller_underscore_name,
                :controller_singular_name,
                :controller_plural_name
  alias_method  :controller_file_name,  :controller_underscore_name
  alias_method  :controller_table_name, :controller_plural_name

  def initialize(runtime_args, runtime_options = {})
    super
    # puts "runtime args: #{runtime_args.inspect}"
    # puts "runtime options: #{runtime_options.inspect}"
    # raise "eccoci!"
    if @name == @name.pluralize && !options[:force_plural]
      logger.warning "Plural version of the model detected, using singularized version.  Override with --force-plural."
      @name = @name.singularize
    end

    @controller_name = @name.pluralize

    base_name, 
      @controller_class_path, 
      @controller_file_path, 
      @controller_class_nesting, 
      @controller_class_nesting_depth = extract_modules(@controller_name)
    @controller_class_name_without_nesting, 
      @controller_underscore_name, 
      @controller_plural_name = inflect_names(base_name)
    @controller_singular_name=base_name.singularize
    if @controller_class_nesting.empty?
      @controller_class_name = @controller_class_name_without_nesting
    else
      @controller_class_name = "#{@controller_class_nesting}::#{@controller_class_name_without_nesting}"
    end
  end

  def exists?(class_name)
    # Convert to string to allow symbol arguments.
    class_name = class_name.to_s

    # Skip empty strings.
    return nil if class_name.strip.empty?

    # Split the class from its module nesting.
    nesting = class_name.split('::')
    name = nesting.pop

    # Extract the last Module in the nesting.
    last = nesting.inject(Object) { |last, nest|
      break unless last.const_defined?(nest)
      last.const_get(nest)
    }

    # If the last Module exists, check whether the given
    # class exists.
    last and last.const_defined?(name.camelize)
  end

  def klass(class_name)
    exists?(class_name) ? eval(class_name) : nil
  end
  
  def manifest
    record do |m|
      # Check for class naming collisions.
      m.class_collisions(controller_class_path, "#{controller_class_name}Controller", "#{controller_class_name}Helper")
      m.class_collisions(class_path, "#{class_name}")

      # Depend on model generator but skip if the model exists.
      m.dependency 'model', [singular_name], :collision => :skip, :skip_migration => true

      # Controller, helper, views, test and stylesheets directories.
      m.directory(File.join('app/models', class_path))
      m.directory(File.join('app/controllers', controller_class_path))
      m.directory(File.join('app/helpers', controller_class_path))
      m.directory(File.join('app/views', controller_class_path, controller_file_name))
      m.directory(File.join('app/views/layouts', controller_class_path))
      m.directory(File.join('test/functional', controller_class_path))
      m.directory(File.join('test/unit', class_path))
      m.directory(File.join('public/stylesheets', class_path))
      m.directory(File.join('public/javascripts', class_path))

      # forms
      m.complex_template "form.html.erb",
        File.join('app/views',
                  controller_class_path,
                  controller_file_name,
                  "_form.html.erb"),
        :insert => 'form_detail.html.erb',
        :sandbox => lambda { create_sandbox },
        :begin_mark => 'form',
        :end_mark => 'eoform',
        :mark_id => singular_name,
        :collision => :force    # must change in :skip

      for action in scaffold_views
        m.template(
          "view_#{action}.html.erb",
          File.join('app/views', controller_class_path, controller_file_name, "#{action}.html.erb")
        )
      end

      # Layout and stylesheet.
      m.template('layout.html.erb', File.join('app/views/layouts', controller_class_path, 
        "#{controller_file_name}.html.erb"))
      m.template('style.css', 'public/stylesheets/scaffold.css')
      m.template('controller.rb', File.join('app/controllers', controller_class_path, 
        "#{controller_file_name}_controller.rb"))
      m.template('functional_test.rb', File.join('test/functional', controller_class_path, 
        "#{controller_file_name}_controller_test.rb"))
      m.template('helper.rb', File.join('app/helpers', controller_class_path, 
        "#{controller_file_name}_helper.rb"))
      m.file('form_box_builder.rb', File.join('lib', "form_box_builder.rb"), :collision => :skip)
      m.file('form_box.css', File.join('public/stylesheets', "form_box.css"), :collision => :skip)
      m.file('calendar.css', File.join('public/stylesheets', "calendar.css"), :collision => :skip)
      m.file('calendar.png', File.join('public/images', "calendar.png"), :collision => :skip)
      FileUtils.cp_r File.join(@source_root, 'calendar'), File.join(@destination_root, 'public/javascripts/calendar')

      m.route_resources controller_file_name


      # m.dependency 'model', [name] + @args, :collision => :skip
    end
  end

  protected
    # Override with your own usage banner.
    def banner
      "Usage: #{$0} quick ModelName [field:type, field:type]"
    end

    def add_options!(opt)
      opt.separator ''
      opt.separator 'Options:'
      opt.on("--skip-timestamps",
             "Don't add timestamps to the migration file for this model") { |v| options[:skip_timestamps] = v }
      opt.on("--skip-migration",
             "Don't generate a migration file for this model") { |v| options[:skip_migration] = v }
      opt.on("--force-plural",
             "Forces the generation of a plural ModelName") { |v| options[:force_plural] = v }
    end

    def scaffold_views
      %w[ index show new edit ]
    end

    def model_name
      class_name.demodulize
    end

    def attributes
      klass(@class_name).columns
    end
    
  protected

    # def trestle_views
    #   %w(edit list new show)
    # end

    # def trestle_actions
    #   %w(destroy edit list new show)
    # end

    # def nontrestle_actions
    #   args - trestle_actions
    # end

    def suffix
      "_#{singular_name}" if options[:suffix]
    end

    def create_sandbox
      sandbox = QuickSandbox.new
      sandbox.singular_name = singular_name
      begin
        sandbox.model_instance = model_instance
        sandbox.instance_variable_set("@#{singular_name}", sandbox.model_instance)
      rescue ActiveRecord::StatementInvalid => e
        logger.error "Before updating from new DB schema, try creating a table for your model (#{class_name})"
        raise SystemExit
      end
      sandbox.suffix = suffix
      sandbox
    end

    def model_instance
      base = class_nesting.split('::').inject(Object) do |base, nested|
        break base.const_get(nested) if base.const_defined?(nested)
        base.const_set(nested, Module.new)
      end
      unless base.const_defined?(@class_name_without_nesting)
        base.const_set(@class_name_without_nesting, Class.new(ActiveRecord::Base))
      end
      class_name.constantize.new
    end
end
