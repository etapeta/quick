# Description
# -----------
# This form builder creates fields in a form on a DRY principle.
# It decides the type of control to lay out based on the field type.
# It interprets fields as columns, relationships or attributes.
#
# This form builder can even be given a proxy object implementing 
# a 'meta_fields' class method giving information about unknown 
# or virtual fields.
# 
# The form builder directly generates field labels.
# To support internationalization, the labels are generated using
# an external function:
#     h(:field_<field_name>)
# The GLoc localization plugin offers this function.
#
# Sample view code:
#
# <% form_for :product, @product, :url => { :action => 'update', :id => @product },
#  	:builder => FormBoxBuilder, :lang => current_language do |f| %>
#
#   <%= f.field :name, :required => true %>
#   <%= f.field :product, :choices => @products, :required => true, :show => :full_name %>
#   <%= f.field :url %>
#   <%= f.field :notified, :visual => 'radio' %>
#   <%= f.field :published_on %>
#   <%= f.submit 'Save' %>
#
# <% end %>
#
# CSS Styling
# -----------
# Every field emitted follows this convention (where $FORM and $FIELD
# are the names of the form and field respectively)
# 
# <div class="irow" id="irow_$FORM_$FIELD">
#   <div class="label"><label for="$FORM_$FIELD"><%= l(:field_$FIELD) %></label></div>
#   <div class="input">
#     ... (control or wodget code) ...
#   </div>
#   <div style="clear:both"></div>
# </div>
#
# This HTML format is easyly CSS-stylizable, allowing layouts with labels and fields 
# on the same line or one over the other, or separators between fields, or else.
#
# If you want to change the container of the single field, redefine the two methods 
# :wrap_row and :wrap_block
#
# Naming Convention
# a form shows all its fields in the same way: f.field :method, options [, html_options]
# but there are times when the developer want a more fined control over the fields.
# So it would be useful to estabilish a naming convention in order to consider:
# - a particular input field
# - the presence of the label
#
# TODO:
# [ ] find a naming convention for methods.
# [ ] add field message
# [ ] add explicit label with string or symbol
# [ ] check label existence in language
# [ ] accept choice in string format
# [ ] check types from other sources
# [ ] add support for N:1 relationships (drop-down or uneditable externally filled text-field or label)
# [ ] add support for 1:N relationships (check-box set or externally filled list)
# [ ] if form.options[:read_only] => only labels
# [ ] date time in different formats: date, time, date+time
# [ ] time field (time, datetime, timestamp)
class FormBoxBuilder < ActionView::Helpers::FormBuilder
  include GLoc if Object.const_defined?('GLoc')   # opzionale se si definisce ApplicationHelper::l(sym)
  include ApplicationHelper
  include ActionView::Helpers::TagHelper
  include ActionView::Helpers::JavaScriptHelper
  include ActionView::Helpers::UrlHelper
  include ActionView::Helpers::FormOptionsHelper
  # include ActionController::UrlWriter
  include ActionView::Helpers::FormTagHelper  # for submit_tag :( is there a better way to use a single method from a helper?

  def initialize(object_name, object, template, options, proc)
    super
    # set_language_if_valid options.delete(:lang)
  end

  def read_only?
    @options[:read_only]
  end
  
  def fields_for(object_name, *args, &block)
    raise ArgumentError, "Missing block" unless block_given?
    # options = args.extract_options!
    object  = args.first

    builder = options[:builder] || self.class
    yield builder.new(object_name, object, @template, options, block)
  end

  def wrap_row(method, contents)
    content_tag('div', 
      contents + cr,
      {:class => 'irow', :id => "irow_#{@object_name}_#{method}"})
  end
  
  # puts the content of block inside a wrap row
  def wrap_block(method, options = {}, &block)
    # content = capture(&block)
    concat(tag('div', {:class => 'irow', :id => "irow_#{@object_name}_#{method}"}), block.binding)
    concat(label_for_field(method, options), block.binding)
    concat(tag('div', {:class => 'input'}), block.binding)
    yield self
    concat(cr, block.binding)
    concat('</div>', block.binding)
    concat('</div>', block.binding)
  end

  # in teoria, questo dovrebbe esser il giusto di wrap_block, ma non funziona
  # def wrap_block(method, options = {}, &block)
  #   wrap_row(method,  
  #     label_for_field(method, options) + content_tag('div', capture(&block), :class => 'input'))
  # end

  def field(method, options = {}, html_options = {}, &block)
    return wrap_block(method, options, &block) if block_given?

    # determine the type of control required
    type = type_for_field(method, options)

    # msg = (@options[:read_only] || options[:read_only]) ? :constant_field : :input_field
    # hfield = self.send(msg, method, type, options, html_options)

    hfield = if @options[:read_only] || options[:read_only]
      constant_field(method, type, options, html_options)
    else
      input_field(method, type, options, html_options)
    end
    
    #
    # and relations ??????  
    # type == nil, sometimes columns[method + '_id'], but better check the rel at class level
    #
    wrap_row(method, 
      label_for_field(method, options) + 
      content_tag('div', hfield, :class => 'input'))
  end

  def submit(value = "Save changes", options = {})
    link_options = { :name => 'commit', :type => 'submit', :value => value }
    link_options[:onclick] = "RedBox.showInline('#{options[:splash]}'); return true;" if options[:splash]
    wrap_row('submit', 
      content_tag('div', submit_tag(value, options), :class => 'input submit')) 
  end

  LANGS = ['ar','en','fr','sp']
  LANG_LABELS = {'ar' => 'Arabic','en' => 'English','fr' => 'French','sp' => 'Spanish'}
  DEFAULT_LANG = 'en'

  def language_area(method, options = {}, html_options = {})
    @controller = @template.controller  # serve per generare la url_for di link_to_remote via UrlHelper
    ajax_controller = 'products'        # riceve la richiesta ajax per il cambio di linguaggio
    read_only = @options[:read_only] || options[:read_only]
    langtabs = LANGS.collect do |lang|
      ajaxlink = link_to_remote(LANG_LABELS[lang], 
				:url => {
				  :action => :show_language, 
				  :fname => (@object_name.to_s + "_" + method.to_s), 
				  :lang => lang, 
				  :read_only => read_only ? 'Y' : 'N'
				})
      @template.content_tag("div", ajaxlink, 
        :id => "#{@object_name}_#{method}_tab_#{lang}",
        :class => 'langtab' + (lang == DEFAULT_LANG ? " sel" : ""))
		end
		tabbar = @template.content_tag("div", langtabs.join(""), :class => "tabbar")
		textareas = LANGS.collect do |lang|
		  disp = lang == DEFAULT_LANG ? "block" : "none"
		  opts = { :style => "display:#{disp}", :class => "lang_text" }
  		if read_only
  		  opts[:id] = "#{@object_name}_#{method}_#{lang}"
  		  email_template = @object.send("#{method}_#{lang}".to_sym) || ''
        @template.content_tag("div", email_template.gsub("\n", '<br/>'), opts)
      else
  		  opts[:cols] = options[:cols] if options[:cols]
  		  opts[:rows] = options[:rows] || 10
        text_area "#{method}_#{lang}", opts
      end
		end
		wrap_row(method,
		  label_for_field(method, options) + 
		    @template.content_tag("div", tabbar + tag('br') + textareas.join(""), :class => "input tabbable"))
  end

  def password(method, options = {}, html_options = {})
    html_options[:size] = options[:cols] if options[:cols]
    html_options[:size] = options[:size] if options[:size]
    hfield = password_field(method, html_options)
    wrap_row(method, 
      label_for_field(method, options) + content_tag('div', hfield, :class => 'input'))
  end

  # label for a field (yet to be enclosed in irow div)
  def label_for_field(method, options = {})
    return '' if options[:no_label]
    label_text = options.delete(:label) || l(("field_"+method.to_s.gsub(/\_id$/, "")).to_sym)
    label_text += @options[:read_only] ? ":" : options[:required] ? @template.content_tag("span", " *", :class => "required"): ""
    @template.content_tag("div",
      @template.content_tag("label", label_text, 
        :class => (object_has_errors?(method) ? "error" : nil), 
        :for => "#{@object_name}_#{method}"), 
      :class => "label")
  end

  def input_field(method, type, options = {}, html_options = {})
    case
      when type == :text || (type == :string && options[:rows])
        # text_area
        text_area_field(method, options, html_options)
      when [:integer, :string].include?(type) && options[:choices] && options[:radio]
        # radio_button
        radio_group_field(method, options)
      when [:integer, :string].include?(type) && options[:choices]
        # select
        select_field(method, options, html_options)
      when type == :string
        # text_field 
        string_field(method, options, html_options)
      when [:integer, :float, :decimal].include?(type) 
        # text_field (with javascript validation) 
        string_field(method, {:size => 10}.merge(options), html_options)
      when type == :boolean && options[:radio]
        # radio_button
        boolean_radio_group_field(method, options)
      when type == :boolean
        # check_box
        check_box_field(method, options)
      when [:date, :datetime, :timestamp, :time].include?(type)
        # calendar_field
        calendar_field(method, options, html_options)
  	  when type == :belongs_to
  	    # no clue about which choices: argue all instances of that type
        select_one_external_field(method, options, html_options)
      when type == :has_many
        select_many_external_fields(method, options, html_options)
      when type == :binary
        # ???
        raise "unknown field type"
      else
        # text_field (or check the value)
        string_field(method, options, html_options)
      end
  end
  
  def string_field(method, options, html_options)
    html_options[:size] = options[:cols] if options[:cols]
    html_options[:size] = options[:size] if options[:size]
    html_options[:readonly] = "readonly" if options[:read_only]
    text_field(method, html_options)
  end
  
  def text_area_field(method, options, html_options)
    html_options[:rows] = options[:rows] if options[:rows]
    html_options[:cols] = options[:cols] if options[:cols]
    html_options[:readonly] = "readonly" if options[:read_only]
    hfield = text_area(method, html_options)
  end
  
  def radio_group_field(method, options)
    buttons = []
    as_choices(options[:choices]).each do |text,value|
      buttons << ext_radio_button(method, options, type, text, value)
    end
    hfield = buttons.join('<br/>')
  end

  def boolean_radio_group_field(method, options)
    required = options.delete(:required)
    choices = options.delete(:choices)
    choices = as_choices(choices) || [['No', '0'], ['Yes', '1']]
    raise "invalid select's options" unless choices.size == 2
    ext_radio_button(method, options, type, choices[0].first, choices[0].last) +
      ext_radio_button(method, options, type, choices[1].first, choices[1].last)
  end

  def check_box_field(method, options)
    options.delete(:required)
    check_box(method, options)
  end

  def calendar_field(method, options, html_options)
    # NOTE: Use internal format %Y-%m-%d to easily update record
    hid = "#{@object_name}_#{method}"
    html_options = html_options.merge({:size => 10}) unless html_options[:size]
    text_field(method, html_options) +
      tag('img', {
        :alt => "Calendar", 
        :class => "calendar-trigger", 
        :id => "#{hid}_trigger",
        :src => "/images/calendar.png",
        }) + 
      javascript_tag("Calendar.setup({
					inputField : '#{hid}', 
					ifFormat : '%Y/%m/%d',
					button : '#{hid}_trigger' 
				});")
  end
  
  def select_field(method, options, html_options)
    options[:include_blank] = true unless options.delete(:required)
    unless options[:selected]
      sel_obj = @object.send(method)
      sel_obj = sel_obj.id if sel_obj.is_a?(ActiveRecord::Base)
      options[:selected] = sel_obj
    end
    select(method, as_choices(options[:choices], options[:show]), options, html_options)
  end

  def select_one_external_field(method, options, html_options)
    # candidates
    unless options[:choices]
      klass_name = @object.class.reflections[method].options[:class_name] if @object.class.reflections[method].options
      klass_name ||= method.to_s.camelize
      options[:choices] = klass_name.constantize.find(:all)
    end
    column = @object.class.reflections[method].options[:foreign_key] if @object.class.reflections[method].options
    column ||= "#{method}_id"
    select_field(column, options, html_options)
  end

  def select_many_external_fields(method, options, html_options)
    # candidates
    unless options[:choices]
      klass_name = @object.class.reflections[method].options[:class_name] if @object.class.reflections[method].options
      klass_name ||= method.to_s.camelize
      options[:choices] = klass_name.constantize.find(:all)
    end
    candidates = as_choices(options[:choices], options[:show])
    elects = as_choices(@object.send(method), options[:show]).collect(&:last)
    cboxes = candidates.collect {|c| 
      check_box_tag("#{@object_name}[#{method}][]", c.last, elects.include?(c.last)) + " #{c.first}"
    }
    if options[:rows]
      nr, nc = options[:rows], (1 + (candidates.size - 1) / options[:rows])
      # @object.logger.info ">>>>>> #{nr} x #{nc}"
      content_tag('table', 
        (0...nr).collect {|r| 
          content_tag('tr', 
            (0...nc).collect {|c| 
              content_tag('td', cboxes[c + r * nc])
            }.join)
        }.join)
    elsif options[:cols]
      nr, nc = (1 + (candidates.size - 1) / options[:cols]), options[:cols]
      content_tag('table', 
        (0...nr).collect {|r| 
          content_tag('tr', 
            (0...nc).collect {|c| 
              content_tag('td', cboxes[c + r * nc])
            }.join)
        }.join)
    else
      return cboxes.join('<br/>')
    end
  end

  # NOTE: The rating field has not been integrated into the :field method
  # If you use it, you have to put manually the label and the container
  # NOTE: html_options are currently ignored since we have no container.
  # This method currently requires the inclusion of ratings.js and rating.css.
  def rating_field(method, options = {}, html_options = {})
    value = @object.send(method) rescue nil
    value = 0 if value.blank?
    name = "#{@object_name}[#{method}]"
    xname = name.gsub(/\]/,'').gsub(/[^a-zA-Z0-9_]/,'_')
    js = "var rating_#{xname} = new Control.Rating('rating_#{xname}',{input: 'ftext_#{xname}', multiple: true});rating_#{xname}.setValue(#{value});"
    hid = if options[:drop_down]
      select_tag(name, options_for_select([['','']] + (1..6).collect {|i| [i.to_s,i.to_s] }), :id => "ftext_#{xname}")
    else
      hidden_field_tag(name, '', :id => "ftext_#{xname}")     # automatically filled through js
    end
    if @options[:read_only] || options[:read_only]
      js = "new Control.Rating('rating_#{xname}',{value: #{value}, rated: true});"
      hid = ''
    end
    content_tag('div', '', :class => 'rating_container', :id => "rating_#{xname}") + hid + javascript_tag(js)
  end
  
  def constant_field(method, type, options, html_options)
    hfield = nil
    value = @object.send(method) rescue nil
	  if options[:choices] && [:string, :belongs_to].include?(type)
	    hfield = options[:show] ? h(value.send(options[:show])) :
	      h(option_text(options[:choices], value) || value)
    elsif [:string, :text, :integer, :float, :decimal].include?(type)
      hfield = h(value).gsub("\n","<br/>")
    elsif type == :boolean
      # image
      text = value ? "Yes" : "No"
      hfield = options[:icon] ? tag('img', {
        :alt => text, 
        :src => "/images/#{value ? 'true' : 'false'}.png",
        }) : check_box(method, :disabled => true) # oppure text
    elsif type == :date
      hfield = format_date(value)
      # date_format ||= (Setting.date_format.blank? || Setting.date_format.size < 2 ? l(:general_fmt_date) : Setting.date_format)
      # hfield = date.strftime(date_format)
    elsif [:datetime, :timestamp, :time].include?(type)
      hfield = format_time(value)
    elsif type == :belongs_to
      # raise "missing :show options in field" unless options[:show]
      hfield = h(value.send(shower_for(value, options[:show]))).gsub("\n","<br/>")
    elsif type == :has_many
      hfield = h(as_choices(value, options[:show]).collect(&:first).join(','))
    elsif type == :binary
      # ???
      raise "unknown field type"
    else
      # text_field (or check the value)
      hfield = h("#{value}")
    end
    # return text in div so you can easily css-stylize it
    content_tag('div', hfield, :class => "constfield")
  end
  
  # Determines the type of a field.
  # Possible results:
  #   :string (default)
  #   :text
  #   :integer
  #   :float
  #   :boolean
  #   :decimal
  #   :time
  #   :date
  #   :timestamp
  #   :datetime
  #   :belongs_to
  #   :has_one
  #   :has_many
  # La ricerca avviene nel seguente modo:
  # - Se la classe dell'oggetto implementa un metodo :meta_field
  #      def self.meta_field(method)
  #      end
  #   che ritorna il tipo di campo corrispondente ad un metodo, si usa quello.
  # - Se la classe e' un ActiveRecord, e il metodo cercato e' tra le :columns
  #   della classe, il tipo viene assunto dalla colonna stessa.
  # - Se la classe e' un ActiveRecord e il metodo rappresenta una relazione, 
  #   il tipo viene assunto dalla relazione stessa.
  # - In ogni altro caso, si assume il tipo come :string 
  def type_for_field(method, options)
    if @object.nil?
      :string
    elsif @object.class.respond_to?(:meta_field)
      @object.class.meta_field(method)
    elsif (col = @object.class.columns && @object.class.columns.detect {|col| col.name == method.to_s })
      col.type
    elsif (rel = @object.class.reflections[method])
      # is method a relationship?
      raise "relationship not managed yet" unless [:belongs_to, :has_many].include?(rel.macro)
      rel.macro
    else
      :string
    end
  end
  
  # NOTA: Rails 2.0 richiede questo metodo, probabilmente legato al sistema di autenticazione interno
  def protect_against_forgery?
    false
  end

  protected

  def concat(string, binding)
    eval(ActionView::Base.erb_variable, binding) << string
  end

  def cr
    content_tag('div', '', :style => "clear:left")
  end

  POSSIBLE_SHOWERS = [:name]

  def shower_for(obj, shower = nil)
    return shower if shower
    POSSIBLE_SHOWERS.each do |shower|
      return shower if obj.respond_to?(shower)
    end
    :to_s
  end
  
  def as_choices(cho, shower = nil)
    return cho if cho.empty? or cho.first.is_a?(Array)
    if cho.first.is_a?(ActiveRecord::Base)
      return cho.collect {|c| [c.send(shower), c.id] } if shower
      POSSIBLE_SHOWERS.each do |shower|
        return cho.collect {|c| [c.send(shower), c.id] } if cho.first.respond_to?(shower)
      end
      cho.collect {|c| [c.to_s, c.id] } 
    end
    nil
  end

  def option_text(choices, value)
    choices.each do |cho|
      return cho.first if cho.last == value
    end
    nil
  end
  
  def ext_radio_button(method, options, type, text, value)
    realvalue = @object.send(method.to_sym) rescue nil
    options.delete(:required)
    options.delete(:radio)
    checked = (type == :boolean) ? ((realvalue.nil? || realvalue == false) == (value == '0')) : (realvalue.to_s == value.to_s)
    options = options.merge({:checked => "checked"}) if checked
    radio_button(method, value, options) + text.to_s
  end

  def object_has_errors?(method)
    return false unless @object
    return false unless @object.respond_to?(:errors)
    @object.errors[method]
  end  

end
