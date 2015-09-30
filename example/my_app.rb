## Test app for Framework
class MyApp < Flame::Application
	mount HomeController

	mount UsersController, '/users' do
		# get '/', :index
		# post '/', :create
		# get '/:id', :show
		# put '/:id', :update
		# delete '/:id', :delete
		rest
		defaults
	end
end
