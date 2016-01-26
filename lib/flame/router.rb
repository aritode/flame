require_relative 'route'
require_relative 'validators'

module Flame
	## Router class for routing
	class Router
		attr_reader :app, :routes, :hooks

		def initialize(app)
			@app = app
			@routes = []
			@hooks = {}
		end

		def add_controller(ctrl, path, block = nil)
			## TODO: Add Regexp paths

			## Add routes from controller to glob array
			ctrl.include(*@app.helpers)
			route_refine = RouteRefine.new(self, ctrl, path, block)
			concat_routes(route_refine) if ActionsValidator.new(route_refine).valid?
		end

		## Find route by any attributes
		def find_route(attrs)
			route = routes.find { |r| r.compare_attributes(attrs) }
			route.dup if route
		end

		## Find the nearest route by path parts
		def find_nearest_route(path_parts)
			while path_parts.size >= 0
				route = find_route(path_parts: path_parts)
				break if route || path_parts.empty?
				path_parts.pop
			end
			route
		end

		## Find hooks by Route
		def find_hooks(route)
			result = {}
			hooks[route[:controller]].each do |type, hash|
				if type == :error
					result[type] = hash
				else
					result[type] = (hash[route[:action]] || []) | (hash[:*] || [])
				end
			end
			# p result
			result
		end

		private

		def concat_routes(route_refine)
			routes.concat(route_refine.routes)
			hooks[route_refine.ctrl] = route_refine.hooks
		end

		## Helper module for routing refine
		class RouteRefine
			attr_accessor :rest_routes
			attr_reader :ctrl, :routes, :hooks

			HOOK_TYPES = [:before, :after, :error].freeze

			def self.http_methods
				[:GET, :POST, :PUT, :DELETE]
			end

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
				@hooks = HOOK_TYPES.each_with_object({}) { |type, hash| hash[type] = {} }
				execute(&block)
			end

			http_methods.each do |request_method|
				define_method(request_method.downcase) do |path, action = nil|
					if action.nil?
						action = path.to_sym
						path = "/#{path}"
					end
					ArgumentsValidator.new(@ctrl, path, action).valid?
					add_route(request_method, path, action)
				end
			end

			HOOK_TYPES.each do |type|
				default_actions = (type == :error ? 500 : :*)
				define_method(type) do |actions = default_actions, action = nil, &block|
					actions = [actions] unless actions.is_a?(Array)
					actions.each { |a| (@hooks[type][a] ||= []).push(action || block) }
				end
			end

			def defaults
				rest
				@ctrl.public_instance_methods(false).each do |action|
					next if find_route_index(action: action)
					add_route(:GET, nil, action)
				end
			end

			def rest
				rest_routes.each do |rest_route|
					action = rest_route[:action]
					if @ctrl.public_instance_methods.include?(action) &&
					   find_route_index(action: action).nil?
						add_route(*rest_route.values, true)
					end
				end
			end

			def mount(ctrl, path = nil, &block)
				path = path_merge(
					@path,
					(path || ctrl.default_path(true))
				)
				@router.add_controller(ctrl, path, block)
			end

			private

			def execute(&block)
				block.nil? ? defaults : instance_exec(&block)
				@router.app.helpers.each do |helper|
					instance_exec(&helper.mount) if helper.respond_to?(:mount)
				end
				# p @routes
				@routes.sort! { |a, b| b[:path] <=> a[:path] }
			end

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
