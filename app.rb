require 'sinatra'
require 'dropbox_sdk'
require 'json'
require 'haml'
require 'coffee-script'
enable :sessions

# database
require 'dm-core'
require 'dm-migrations'
require 'dm-validations'
DataMapper.setup( :default, "sqlite3://#{Dir.pwd}/users.db" )
class User
  include DataMapper::Resource
  property :username, String, :key => true, :required => true, :unique => true, :format => /\w+/
  property :dropbox_session, Text
  property :referral_link, String
  property :display_name, String
  property :email, String
  property :uid, String
  property :country, String
  property :quota, Integer
  property :shared, Integer
  property :normal, Integer
  property :created_at, DateTime
end
# Automatically create the tables if they don't exist
DataMapper.auto_migrate!

# dropbox api
dbkey, dbsecret = 'ribh7ft60gym2l8', 'sj8rz89ril4wl76'

# ----------------------------------------------

# user visits homepage
# user enters desired username
# app checks that username isn't already registered
  # if yes -> redirect to home page with error message
# app stores dbsession and desired username in session
# dropbox authenticates
# app creates user from session's username, dbtoken, and info from /account/info
  # doublechecks that username isn't taken
# app shows user registered page with link to their dropbox dropbox

# person visits link
# app looks up access token based on username
#   if doesn't exist, show "user does not exist"
# if exists, look up access token and use that

get '/' do
  if !params[:oauth_token]
    # first-time user!
    haml :index
  else
    # the user has returned from Dropbox
    # we've been authorized, so now request an access_token
    dbsession = DropboxSession.deserialize(session[:dropbox_session])
    dbsession.get_access_token

    dbclient = DropboxClient.new(dbsession)

    # get info from dropbox
    account_info = dbclient.account_info
    puts "account_info = #{account_info}"
    quota = account_info["quota_info"]
    
    @user = User.new(
      username: session[:username],
      dropbox_session: dbsession.serialize,
      referral_link: account_info["referral_link"],
      display_name: account_info["display_name"],
      uid: account_info["uid"],
      country: account_info["country"],
      quota: quota["quota"],
      normal: quota["normal"],
      shared: quota["shared"],
      created_at: Time.now
    )
    p @user

    if @user.save
      haml :registered
    else
      # show @user.errors
      "there were errors saving: #{@user.errors.map{|e| e.to_s}}"
    end
  end
end

# request a username
post '/' do
  username = params['username']

  if User.get(username) || !username =~ /\w+/
    # username already exists/is of the wrong format
    # redirect to / with errors
  else
    dbsession = DropboxSession.new(dbkey, dbsecret)
    session[:dropbox_session] = dbsession.serialize #serialize and save this DropboxSession
    session[:username] = username

    # send them out to authenticate us
    redirect dbsession.get_authorize_url("http://127.0.0.1:9393/")
  end

  "something went wrong"
end

def get_session
  # Check if user has no dropbox session...re-direct them to authorize
  redirect '/' unless session[:dropbox_session]
  @dbsession = DropboxSession.deserialize(session[:dropbox_session])
  @client = DropboxClient.new(@dbsession, :app_folder) #raise an exception if session not authorized
  @info = @client.account_info # look up account information
end

get "/js/app.js" do
  content_type "text/javascript"
  coffee File.open("./app.coffee").read
end

get '/upload' do
  puts "GETTING /upload"
  get_session
  # show a file upload page
  haml :upload
end

post '/upload' do
  puts "POSTING TO /upload"
  p params
  get_session

  # upload the posted file to dropbox keeping the same name
  resp = params[:files].map do |file|
    @client.put_file(file[:filename], file[:tempfile].read)
  end

  resp.map{|f|
    f[:name] = f["path"].gsub(/^\//,'')
    f[:size] = f["bytes"]
    f[:url] = "hi"
    f[:thumbnail_url] = "hi"
    f[:delete_url] = ""
    f[:delete_type] = "DELETE"
  }
  p resp
  content_type :json
  resp.to_json
end


get "/:username" do
  @user = User.get(params[:username])
  return "User not found<br />#{User.all.map(&:to_s)}" unless @user
  haml :upload
end