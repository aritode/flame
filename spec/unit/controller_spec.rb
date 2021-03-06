# frozen_string_literal: true

module ControllerTest
	## Controller for Controller tests
	class OneController < Flame::Controller
		def foo(first, second = nil); end

		def bar
			view
		end

		def baz
			reroute AnotherOneController, :baz
		end

		def object_hash
			hash
		end

		def respond_for_reroute
			'Hello from reroute'
		end

		def current_reroute
			reroute :respond_for_reroute
		end

		def hash_reroute
			reroute :object_hash
		end

		def index_reroute
			reroute AnotherOneController
		end

		def execute_reroute
			reroute AnotherOneController, :bar
		end

		def hooks_reroute
			reroute AnotherOneController, :hooked
		end

		post '/refinement_path_for_create',
			def create; end
	end

	## Another controller for Controller tests
	class AnotherOneController < Flame::Controller
		def index
			'Another index'
		end

		def hello(name = 'world'); end

		def bar; end

		def baz
			'Another baz'
		end

		def hooked
			'Another hooked'
		end

		def back
			path_to_back
		end

		protected

		def execute(method)
			return body 'Another execute' if method == :bar

			super

			'after-hook' if method == :hooked
		end
	end

	class RefinedPathController < Flame::Controller
		PATH = '/that_path_is_refined'
	end

	module Nested
		class IndexController < Flame::Controller
			def index; end
		end

		class NestedController < Flame::Controller
			def back
				path_to_back
			end
		end
	end

	module ForeignPublicMethods
		def cache; end
	end

	## Module for Controller tests
	module SomeActions
		include ForeignPublicMethods
		extend Flame::Controller::Actions

		def included_action; end

		def another_included_action; end

		post '/refined_path',
			def refined_action; end

		private

		def private_included_method; end
	end

	## Application for Controller tests
	class Application < Flame::Application
		mount OneController, '/'
		mount AnotherOneController, '/another'

		mount Nested::IndexController do
			mount Nested::NestedController
		end
	end
end

describe Flame::Controller do
	let(:env) do
		{
			Rack::RACK_URL_SCHEME => 'http',
			Rack::SERVER_NAME => 'localhost',
			Rack::SERVER_PORT => 3000,
			Rack::RACK_INPUT => StringIO.new
		}
	end

	let(:dispatcher) { Flame::Dispatcher.new(ControllerTest::Application, env) }

	let(:controller_class) { ControllerTest::OneController }

	let(:controller) { controller_class.new(dispatcher) }

	describe '.actions' do
		subject { controller_class.actions }

		it do
			is_expected.to eq(
				ControllerTest::OneController.public_instance_methods(false)
			)
		end
	end

	describe '.path' do
		subject { controller_class.path }

		context 'without PATH constant (default)' do
			context 'one-word named controller' do
				let(:controller_class) { ControllerTest::OneController }

				it { is_expected.to eq '/one' }
			end

			context 'two-word named controller' do
				let(:controller_class) { ControllerTest::AnotherOneController }

				it { is_expected.to eq '/another_one' }
			end

			context 'nested in module index controller' do
				let(:controller_class) { ControllerTest::Nested::IndexController }

				it { is_expected.to eq '/nested' }
			end
		end

		context 'with PATH constant (refined)' do
			let(:controller_class) { ControllerTest::RefinedPathController }

			it { is_expected.to eq '/that_path_is_refined' }
		end
	end

	describe 'delegators' do
		subject { controller.methods }

		it do
			is_expected.to include(
				:config, :request, :params, :halt, :session, :response,
				:status, :body, :default_body
			)
		end
	end

	describe '#initialize' do
		subject { controller_class.new(dispatcher) }

		describe '@dispatcher' do
			subject { super().instance_variable_get(:@dispatcher) }

			it { is_expected.to eq dispatcher }
		end
	end

	describe '#cookies' do
		subject { controller.cookies }

		it { is_expected.to be_instance_of Flame::Controller::Cookies }

		it { is_expected.to be controller.cookies }
	end

	describe '#path_to' do
		subject { controller.path_to(*args) }

		context 'another controller and action' do
			let(:args) { [ControllerTest::AnotherOneController, :baz] }

			it { is_expected.to eq '/another/baz' }
		end

		context 'another controller without action' do
			let(:args) { [ControllerTest::AnotherOneController] }

			it { is_expected.to eq '/another' }
		end

		context 'action without controller' do
			let(:args) { [:bar] }

			it { is_expected.to eq '/bar' }
		end

		context 'action with arguments' do
			let(:args) { [:foo, first: 'Alex'] }

			it { is_expected.to eq '/foo/Alex' }
		end
	end

	describe '#url_to' do
		subject { controller.url_to(*args, **kwargs) }

		context 'String path' do
			let(:args) { ['/some/path?with=args'] }
			let(:kwargs) { {} }

			it { is_expected.to eq 'http://localhost:3000/some/path?with=args' }

			context 'default port for scheme' do
				let(:env) do
					{
						Rack::RACK_URL_SCHEME => 'http',
						Rack::SERVER_NAME => 'example.domain',
						Rack::SERVER_PORT => 80,
						Rack::RACK_INPUT => StringIO.new
					}
				end

				it { is_expected.to eq 'http://example.domain/some/path?with=args' }
			end

			context 'HTTP host' do
				context 'with port' do
					let(:env) do
						{
							Rack::RACK_URL_SCHEME => 'http',
							Rack::HTTP_HOST => 'localhost:3000',
							Rack::RACK_INPUT => StringIO.new
						}
					end

					it { is_expected.to eq 'http://localhost:3000/some/path?with=args' }
				end

				context 'without port' do
					let(:env) do
						{
							Rack::RACK_URL_SCHEME => 'http',
							Rack::HTTP_HOST => 'example.domain',
							Rack::RACK_INPUT => StringIO.new
						}
					end

					it { is_expected.to eq 'http://example.domain/some/path?with=args' }
				end
			end
		end

		context 'controller and action' do
			let(:args) { [ControllerTest::AnotherOneController, :baz] }
			let(:kwargs) { {} }

			it { is_expected.to eq 'http://localhost:3000/another/baz' }
		end

		context 'action and argument' do
			let(:args) { [:foo] }
			let(:kwargs) { { first: 'Alex' } }

			it { is_expected.to eq 'http://localhost:3000/foo/Alex' }
		end

		context 'Flame::Path object' do
			let(:args) { [Flame::Path.new('/some/path?with=args')] }
			let(:kwargs) { {} }

			it { is_expected.to eq 'http://localhost:3000/some/path?with=args' }
		end

		context 'static file with version' do
			let(:file) { 'test.txt' }
			let!(:mtime) { File.mtime File.join(__dir__, 'public', file) }
			let(:times) { 5 }

			before do
				controller.config[:environment] = environment
			end

			shared_examples 'correct URL' do
				before do
					expect(File).to receive(:mtime).and_call_original
						.exactly(expected_times).times
				end

				it do
					times.times do
						expect(
							controller.url_to("/#{file}", version: true)
						).to eq(
							"http://localhost:3000/#{file}?v=#{mtime.to_i}"
						)
					end
				end
			end

			context 'production environment' do
				let(:environment) { 'production' }
				let(:expected_times) { 1 }

				it_behaves_like 'correct URL'
			end

			context 'development environment' do
				let(:environment) { 'development' }
				let(:expected_times) { times }

				it_behaves_like 'correct URL'
			end
		end
	end

	describe '#path_to_back' do
		let(:controller_class) { ControllerTest::AnotherOneController }
		subject { controller.back } ## it's action with `path_to_back`

		context 'referer URL exists' do
			let(:referer) { 'http://example.com/' }
			let(:env) { super().merge('HTTP_REFERER' => referer) }

			it { is_expected.to eq referer }
		end

		context 'referer with the same URL' do
			let(:referer) { 'http://localhost:3000/another/bar' }
			let(:env) do
				super().merge(
					Rack::PATH_INFO => '/another/bar',
					'HTTP_REFERER' => referer
				)
			end

			it { is_expected.not_to eq referer }
		end

		context 'without referer' do
			it { is_expected.to eq '/another' }
		end

		context 'without referer and index action' do
			let(:env) { super().merge(Rack::PATH_INFO => '/nested/nested/back') }
			let(:controller_class) { ControllerTest::Nested::NestedController }

			it { is_expected.to eq '/' }
		end
	end

	describe '#redirect' do
		before do
			controller.redirect(*args)
		end

		context 'by String' do
			let(:url) { 'http://example.com/' }

			context 'without status' do
				let(:args) { [url] }

				describe 'status' do
					subject { controller.status }

					it { is_expected.to eq 302 }
				end

				describe 'location in response' do
					subject { controller.response.location }

					it { is_expected.to eq url }
				end

				describe 'no mutation of of args as array' do
					subject { args }

					it { is_expected.to eq [url] }
				end
			end

			context 'with status as the last arument' do
				let(:args) { [url, 301] }

				describe 'status' do
					subject { controller.status }

					it { is_expected.to eq 301 }
				end

				describe 'location in response' do
					subject { controller.response.location }

					it { is_expected.to eq url }
				end

				describe 'no mutation of of args as array' do
					subject { args }

					it { is_expected.to eq [url, 301] }
				end
			end
		end

		describe 'by controller and action' do
			let(:controller_class) { ControllerTest::AnotherOneController }

			context 'without status' do
				let(:args) { [controller_class, :hello, name: 'Alex'] }

				describe 'status' do
					subject { controller.status }

					it { is_expected.to eq 302 }
				end

				describe 'location in response' do
					subject { controller.response.location }

					it { is_expected.to eq '/another/hello/Alex' }
				end

				describe 'no mutation of of args as array' do
					subject { args }

					it { is_expected.to eq [controller_class, :hello, name: 'Alex'] }
				end
			end

			context 'with status as the last arument' do
				let(:args) { [controller_class, :hello, { name: 'Alex' }, 301] }

				describe 'status' do
					subject { controller.status }

					it { is_expected.to eq 301 }
				end

				describe 'location in response' do
					subject { controller.response.location }

					it { is_expected.to eq '/another/hello/Alex' }
				end

				describe 'no mutation of of args as array' do
					subject { args }

					it do
						is_expected.to eq [controller_class, :hello, { name: 'Alex' }, 301]
					end
				end
			end
		end

		describe 'by URI object' do
			let(:uri) { URI::HTTP.build(host: 'example.com') }

			context 'without status' do
				let(:args) { [uri] }

				describe 'status' do
					subject { controller.status }

					it { is_expected.to eq 302 }
				end

				describe 'location in response' do
					subject { controller.response.location }

					it { is_expected.to eq 'http://example.com' }
				end

				describe 'no mutation of of args as array' do
					subject { args }

					it { is_expected.to eq [uri] }
				end
			end

			context 'with status as the last arument' do
				let(:args) { [uri, 301] }

				describe 'status' do
					subject { controller.status }

					it { is_expected.to eq 301 }
				end

				describe 'location in response' do
					subject { controller.response.location }

					it { is_expected.to eq 'http://example.com' }
				end

				describe 'no mutation of of args as array' do
					subject { args }

					it { is_expected.to eq [uri, 301] }
				end
			end
		end

		describe 'default status' do
			let(:args) { ['http://example.com'] }

			subject { controller.status }

			it { is_expected.to eq 302 }
		end

		describe 'specified status' do
			let(:args) { ['http://example.com', 301] }

			subject { controller.status }

			it { is_expected.to eq 301 }
		end
	end

	describe '#reroute' do
		subject { controller.public_send(action) }

		context 'specified action of specified controller' do
			let(:action) { :baz }

			it { is_expected.to eq 'Another baz' }
		end

		context 'specified action of current controller' do
			let(:action) { :current_reroute }

			it { is_expected.to eq 'Hello from reroute' }
		end

		describe 'no recreation of current controller' do
			let(:action) { :hash_reroute }

			it { is_expected.to eq controller.object_hash }
		end

		describe 'index action by default' do
			let(:action) { :index_reroute }

			it { is_expected.to eq 'Another index' }
		end

		describe 'calling `execute` method of called controller' do
			let(:action) { :execute_reroute }

			it { is_expected.to eq 'Another execute' }
		end

		describe 'saving result of action as body regardless of after-hooks' do
			let(:action) { :hooks_reroute }

			it { is_expected.to eq 'Another hooked' }
		end
	end

	describe '#attachment' do
		before do
			controller.attachment(*args)
		end

		subject { controller.response }

		describe 'Content-Disposition header' do
			subject { super()['Content-Disposition'] }

			describe 'default' do
				let(:args) { [] }

				it { is_expected.to eq 'attachment' }
			end

			describe 'from filename' do
				let(:args) { ['style.css'] }

				it { is_expected.to eq 'attachment; filename="style.css"' }
			end
		end

		describe 'Content-Type header by filename' do
			subject { super()['Content-Type'] }

			describe 'from filename' do
				let(:args) { ['style.css'] }

				it { is_expected.to eq 'text/css' }
			end
		end
	end

	describe '#view' do
		subject(:view_subject) { controller.view(*args, &block) }

		let(:block) { nil }

		context 'partial' do
			let(:args) { [:_partial] }

			it { is_expected.to eq "<p>This is partial</p>\n" }
		end

		context 'view with layout and instance variables' do
			let(:args) { [:view] }

			before do
				controller.instance_variable_set(:@name, 'user')
			end

			it do
				is_expected.to eq <<~CONTENT
					<body>
						<h1>Hello, user!</h1>\n
					</body>
				CONTENT
			end
		end

		context 'view without layout' do
			let(:args) { [:view, layout: false] }

			it { is_expected.to eq "<h1>Hello, world!</h1>\n" }
		end

		context 'template file not found' do
			let(:args) { [:nonexistent] }

			it do
				expect { subject }.to raise_error(
					Flame::Errors::TemplateNotFoundError,
					"Template 'nonexistent' not found for 'ControllerTest::OneController'"
				)
			end
		end

		context 'partial with block' do
			let(:args) { [:_partial_with_block] }
			let(:block) { proc { 'world' } }

			it { is_expected.to eq "<h1>Hello, world!</h1>\n" }
		end

		describe 'cache' do
			subject(:cached_tilts) { ControllerTest::Application.cached_tilts }

			before do
				cached_tilts.clear
				controller.config[:environment] = environment
				view_subject
			end

			subject { cached_tilts.size }

			context 'development environment' do
				let(:environment) { 'development' }
				let(:args) { [:view] }

				it { is_expected.to be_zero }
			end

			context 'production environment' do
				let(:environment) { 'production' }
				let(:args) { [:view, layout: false] }

				it { is_expected.to eq 1 }
			end

			context 'production environment and false value of cache option' do
				let(:environment) { 'production' }
				let(:args) { [:view, cache: false] }

				it { is_expected.to be_zero }
			end

			context 'development environment and true value of cache option' do
				let(:environment) { 'development' }
				let(:args) { [:view, layout: false, cache: true] }

				it { is_expected.to eq 1 }
			end
		end

		describe 'taking controller name as default path' do
			subject { controller.bar }

			it do
				is_expected.to eq <<~CONTENT
					<body>
						This is view for bar method of ControllerTest::OneController\n
					</body>
				CONTENT
			end
		end

		describe '`render` alias' do
			let(:args) { [:view] }

			it { is_expected.to eq controller.render(*args) }
		end
	end

	describe 'actions inheritance' do
		subject { inherited_controller.actions.sort }

		describe '.inherit_actions' do
			let(:inherited_controller) do
				arguments = args
				kwarguments = kwargs
				Class.new(controller_class) do
					inherit_actions(*arguments, **kwarguments)
				end
			end

			context 'without arguments' do
				let(:args) { [] }
				let(:kwargs) { {} }

				it { is_expected.to eq controller_class.actions.sort }

				it 'saves refinements' do
					expect(inherited_controller.refined_http_methods)
						.to eq(controller_class.refined_http_methods)
				end
			end

			context 'specific actions' do
				let(:args) { [%i[foo bar baz]] }
				let(:kwargs) { {} }

				it { is_expected.to eq %i[foo bar baz].sort }

				it 'drops excluded refinements' do
					expect(inherited_controller.refined_http_methods).to be_empty
				end
			end

			context 'excluded actions' do
				let(:args) { [] }
				let(:kwargs) { { exclude: %i[foo bar] } }

				it { is_expected.to eq((controller_class.actions - %i[foo bar]).sort) }
			end
		end

		describe '.with_actions' do
			let(:inherited_controller) do
				arguments = args
				kwarguments = kwargs
				Class.new(controller_class) do
					include with_actions ControllerTest::SomeActions,
						*arguments, **kwarguments
				end
			end

			context 'without arguments' do
				let(:args) { [] }
				let(:kwargs) { {} }

				it do
					is_expected.to eq(
						ControllerTest::SomeActions.public_instance_methods(false).sort
					)
				end

				it 'saves refinements' do
					expect(inherited_controller.refined_http_methods)
						.to eq(ControllerTest::SomeActions.refined_http_methods)
				end

				it 'saves private methods' do
					expect(inherited_controller.private_instance_methods)
						.to include(*ControllerTest::SomeActions.private_instance_methods)
				end
			end

			context 'excluded actions' do
				let(:args) { [] }
				let(:kwargs) { { exclude: %i[included_action] } }

				it do
					is_expected.to eq(
						(
							ControllerTest::SomeActions.public_instance_methods(false) -
								%i[included_action]
						).sort
					)
				end
			end

			context 'only actions' do
				let(:args) { [] }
				let(:kwargs) { { only: %i[included_action] } }

				it do
					is_expected.to eq(
						(
							ControllerTest::SomeActions.public_instance_methods(false) &
								%i[included_action]
						).sort
					)
				end

				it 'drops excluded refinements' do
					expect(inherited_controller.refined_http_methods).to be_empty
				end
			end

			context '+ .inherit_actions' do
				let(:inherited_controller) do
					Class.new(controller_class) do
						inherit_actions
						include with_actions ControllerTest::SomeActions
					end
				end

				it do
					is_expected.to eq(
						(
							ControllerTest::OneController.actions +
								ControllerTest::SomeActions.public_instance_methods(false)
						).sort
					)
				end
			end
		end
	end
end
