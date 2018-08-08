require 'active_record'
require 'unix_crypt'
require 'bcrypt'
require 'phpass'

class CASino::ActiveRecordAuthenticator

  class AuthDatabase < ::ActiveRecord::Base
    self.abstract_class = true
  end

  # @param [Hash] options
  def initialize(options)
    if !options.respond_to?(:deep_symbolize_keys)
      raise ArgumentError, "When assigning attributes, you must pass a hash as an argument."
    end
    @options = options.deep_symbolize_keys
    raise ArgumentError, "Table name is missing" unless @options[:table]
    if @options[:model_name]
      model_name = @options[:model_name]
    else
      model_name = @options[:table]
      if @options[:connection].kind_of?(Hash) && @options[:connection][:database]
        model_name = "#{@options[:connection][:database].gsub(/[^a-zA-Z]+/, '')}_#{model_name}"
      end
      model_name = model_name.classify
    end
    model_class_name = "#{self.class.to_s}::#{model_name}"
    eval <<-END
      class #{model_class_name} < AuthDatabase
        self.table_name = "#{@options[:table]}"
        self.inheritance_column = :_type_disabled
      end
    END

    @model = model_class_name.constantize
    @model.establish_connection @options[:connection]
  end

  def validate(username, password ,authenticator_name)
    p "In validate ========="
    p username
    p password
    p authenticator_name
    user = @model.send("find_by_#{@options[:username_column]}!", username)
    p user
    p @options[:password_column]
    p user.send(@options[:password_column])
    col_name = @options[:password_column]
    password_from_database = user.send(:col_name)
    p password_from_database
    if authenticator_name == "auth_user_by_otp"
      p "in OTP auth"
      p user
      p password_from_database
    elsif valid_password?(password, password_from_database)
      user_data(user)
    else
      false
    end

  rescue ActiveRecord::RecordNotFound
    false
  end

  def load_user_data(username)
    user = @model.send("find_by_#{@options[:username_column]}!", username)
    user_data(user)
  rescue ActiveRecord::RecordNotFound
    nil
  end

  private
  def user_data(user)
    { username: user.send(@options[:username_column]), extra_attributes: extra_attributes(user) }
  end

  def valid_password?(password, password_from_database)
    return false if password_from_database.blank?
    if password_from_database.match(/^\w{32}$/) && password_from_database.match(/[[:xdigit:]{32}]/)
      valid_password_with_md5?(password, password_from_database)
    else
      magic = password_from_database.split('$')[1]
      case magic
      when /\A2a?\z/
        valid_password_with_bcrypt?(password, password_from_database)
      when /\AH\z/, /\AP\z/
        valid_password_with_phpass?(password, password_from_database)
      else
        valid_password_with_unix_crypt?(password, password_from_database)
      end
    end
  end

  def valid_password_with_bcrypt?(password, password_from_database)
    password_with_pepper = password + @options[:pepper].to_s
    BCrypt::Password.new(password_from_database) == password_with_pepper
  end

  def valid_password_with_unix_crypt?(password, password_from_database)
    UnixCrypt.valid?(password, password_from_database)
  end

  def valid_password_with_phpass?(password, password_from_database)
    Phpass.new().check(password, password_from_database)
  end

  def valid_password_with_md5?(password, password_from_database)
    Digest::MD5.hexdigest(password) == password_from_database
  end

  def extra_attributes(user)
    attributes = {}
    extra_attributes_option.each do |attribute_name, database_column|
      attributes[attribute_name] = user.send(database_column)
    end
    attributes
  end

  def extra_attributes_option
    @options[:extra_attributes] || {}
  end
end
