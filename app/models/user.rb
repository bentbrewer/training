class User < ActiveRecord::Base

  hobo_user_model # Don't put anything above this

  fields do
    name          :string, :required
    last_name     :string, :required
    username      :string, :required, :unique, :login => true, :name => true
    email_address :email_address, :required, :unique
    administrator :boolean, :default => false
    trainer       :boolean, :default => false
    timestamps
  end

  has_many :user_trainings, :dependent => :destroy
  has_many :training_events, :through => :user_trainings, :accessible => true
  has_many :training_facilitators, :dependent => :destroy
  has_many :facilitation_events, :through => :training_facilitators, :source => :training_event, :accessible => true

  # This gives admin rights and an :active state to the first sign-up.
  # Just remove it if you don't want that
  before_create do |user|
    if !Rails.env.test? && user.class.count == 0
      user.administrator = true
      user.state = "active"
    end
  end

  def new_password_required_with_invite_only?
    new_password_required_without_invite_only? || self.class.count==0
  end
  alias_method_chain :new_password_required?, :invite_only

  # --- Signup lifecycle --- #

  lifecycle do

    state :invited, :default => true
    state :active

    create :invite,
           :available_to => "acting_user if acting_user.administrator?",
           :subsite => "admin",
           :params => [:username, :name, :last_name, :email_address],
           :new_key => true,
           :become => :invited do
       UserMailer.invite(self, lifecycle.key).deliver
    end

    transition :accept_invitation, { :invited => :active }, :available_to => :key_holder,
               :params => [ :password, :password_confirmation ]

    transition :request_password_reset, { :active => :active }, :new_key => true do
      UserMailer.forgot_password(self, lifecycle.key).deliver
    end

    transition :reset_password, { :active => :active }, :available_to => :key_holder,
               :params => [ :password, :password_confirmation ]

  end

  children :training_events, :facilitation_events

  # --- Permissions --- #

  def create_permitted?
    # Only the initial admin user can be created
    self.class.count == 0
  end

  def update_permitted?
    acting_user.administrator? ||
      (acting_user == self && only_changed?(:username, :name, :last_name, :crypted_password,
                                            :current_password, :password, :password_confirmation))
    # Note: crypted_password has attr_protected so although it is permitted to change, it cannot be changed
    # directly from a form submission.
  end

  def destroy_permitted?
    acting_user.administrator?
  end

  def view_permitted?(field)
    true
  end
end
