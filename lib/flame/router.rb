require_relative 'route'
require_relative 'validators'

module Flame
	## Router class for routing
	class Router
		attr_reader :app, :routes

		def initialize(app)
			@app = app
			@routes = []
		end

		## Add the controller with it's methods to routes
		## @param ctrl [Flame::Controller] class of the controller which will be added
		## @param path [String] root path for controller's methods
		## @param block [Proc, nil] block for routes refine
		def add_controller(ctrl, path, block = nil)
			## @todo Add Regexp paths

			## Add routes from controller to glob array
			route_refine = RouteRefine.new(self, ctrl, path, block)
			if Validators::ActionsValidator.new(route_refine).valid?
				concat_routes(route_refine)
			end
		end

		## Find route by any attributes
		## @param attrs [Hash] attributes for comparing
		## @return [Flame::Route, nil] return the found route, otherwise `nil`
		def find_route(attrs)
			route = routes.find { |r| r.compare_attributes(attrs) }
			route.dup if route
		end

		## Find the nearest route by path parts
		## @param path_parts [Array] parts of path for route finding
		## @return [Flame::Route, nil] return the found nearest route, otherwise `nil`
		def find_nearest_route(path_parts)
			while path_parts.size >= 0
				route = find_route(path_parts: path_parts)
				break if route || path_parts.empty?
				path_parts.pop
			end
			route
		end

		private

		## Add `RouteRefine` routes to the routes of `Flame::Router`
		## @param route_refine [Flame::Router::RouteRefine] `RouteRefine` with routes
		def concat_routes(route_refine)
			routes.concat(route_refine.routes)
		end

		## Helper class for controller routing refine
		class RouteRefine
			attr_accessor :rest_routes
			attr_reader :ctrl, :routes

			def self.http_methods
				[:GET, :POST, :PUT, :DELETE]
			end

			## Defaults REST routes (methods, pathes, controllers actions)
			def rest_routes
				@rest_routes ||= [
					{ method: :GET,     path: '/',  action: :index  },
					{ method: :POST,    path: '/',  action: :create },
					{ method: :GET,     path: '/',  action: :show   },
					{ method: :PUT,     path: '/',  action: :update },
					{ method: :DELETE,  path: '/',  action: :delete }
				]
			end

			def initialize(router, ctrl, path, block)
				@router = router
				@ctrl = ctrl
				@path = path || @ctrl.default_path
				@routes = []
				execute(&block)
			end

			http_methods.each do |request_method|
				## Define refine methods for all HTTP methods
				## @overload post(path, action)
				##   Execute action on requested path and HTTP method
				##   @param path [String] path of method for the request
				##   @param action [Symbol] name of method for the request
				##   @example Set path to '/bye' and method to :POST for action `goodbye`
				##     post '/bye', :goodbye
				## @overload post(action)
				##   Execute action on requested HTTP method
				##   @param action [Symbol] name of method for the request
				##   @example Set method to :POST for action `goodbye`
				##     post :goodbye
				define_method(request_method.downcase) do |path, action = nil|
					if action.nil?
						action = path.to_sym
						path = "/#{path}"
					end
					Validators::ArgumentsValidator.new(@ctrl, path, action).valid?
					add_route(request_method, path, action)
				end
			end

			## Assign remaining methods of the controller
			##   to defaults pathes and HTTP methods
			def defaults
				rest
				@ctrl.public_instance_methods(false).each do |action|
					next if find_route_index(action: action)
					add_route(:GET, nil, action)
				end
			end

			## Assign methods of the controller to REST architecture
			def rest
				rest_routes.each do |rest_route|
					action = rest_route[:action]
					if @ctrl.public_instance_methods.include?(action) &&
					   find_route_index(action: action).nil?
						add_route(*rest_route.values, true)
					end
				end
			end

			## Mount controller inside other (parent) controller
			## @param ctrl [Flame::Controller] class of mounting controller
			## @param path [String, nil] root path for mounting controller
			## @yield Block of code for routes refine
			def mount(ctrl, path = nil, &block)
				path = path_merge(
					@path,
					(path || ctrl.default_path(true))
				)
				@router.add_controller(ctrl, path, block)
			end

			private

			## Execute block of refinings end sorting routes
			def execute(&block)
				block.nil? ? defaults : instance_exec(&block)
				# instance_exec(&@ctrl.mounted) if @ctrl.respond_to? :mounted
				# @router.app.helpers.each do |helper|
				# 	instance_exec(&helper.mount) if helper.respond_to?(:mount)
				# end
				# p @routes
				@routes.sort! { |a, b| b[:path] <=> a[:path] }
			end

			## Build path for the action of controller
			def make_path(path, action = nil, force_params = false)
				## TODO: Add :arg:type support (:id:num, :name:str, etc.)
				unshifted = force_params ? path : action_path(action)
				if path.nil? || force_params
					parameters = @ctrl.instance_method(action).parameters
					parameters.map! { |par| ":#{par[0] == :req ? '' : '?'}#{par[1]}" }
					path = parameters.unshift(unshifted).join('/')
				end
				path_merge(@path, path)
			end

			def action_path(action)
				action == :index ? '/' : action
			end

			def path_merge(*parts)
				parts.join('/').gsub(%r{\/{2,}}, '/')
			end

			def add_route(method, path, action, force_params = false)
				route = Route.new(
					method: method,
					path: make_path(path, action, force_params),
					controller: @ctrl,
					action: action
				)
				index = find_route_index(action: action)
				index ? @routes[index] = route : @routes.push(route)
			end

			def find_route_index(attrs)
				@routes.find_index { |route| route.compare_attributes(attrs) }
			end
		end
	end
end
