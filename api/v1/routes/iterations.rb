require './lib/jobs/analyze'
require './lib/jobs/hello'

module ExercismAPI
  module Routes
    # rubocop:disable Metrics/ClassLength
    class Iterations < Core
      # Mark exercise as skipped.
      # Called from the CLI.
      post '/iterations/:language/:slug/skip' do |language, slug|
        require_key

        if current_user.guest?
          message = "Please double-check your exercism API key."
          halt 401, { error: message }.to_json
        end

        if !Xapi.exists?(language, slug)
          message = "Exercise '#{slug}' in language '#{language}' doesn't exist. "
          message << "Maybe you mispelled it?"
          halt 404, { error: message }.to_json
        end

        exercise_attrs = {
          user_id: current_user.id,
          language: language,
          slug: slug
        }

        exercise = UserExercise.where(exercise_attrs)
          .first_or_initialize(iteration_count: 0)

        if exercise.new_record?
          exercise.save!
        end
        exercise.touch(:skipped_at)
        halt 204
      end

      # Submit an iteration.
      # Called from the CLI.
      post '/user/assignments' do
        request.body.rewind
        data = request.body.read

        if data.empty?
          halt 400, { error: "must send key and code as json" }.to_json
        end

        data = JSON.parse(data)
        user = User.where(key: data['key']).first

        unless user
          message = "unknown api key '#{data['key']}', "
          message << "please check http://exercism.io/account/key and reconfigure"
          halt 401, { error: message }.to_json
        end

        solution = data['solution']
        if solution.nil?
          solution = { data['path'] => data['code'] }
        end

        # old CLI, let's see if we can hack around it.
        if data['language'].nil?
          path = data['path'] || solution.first.first
          path = path.gsub(/^\//, "")
          segments = path.split(/\\|\//)
          if segments.length < 3
            # nothing we can do.
            halt 400, "please upgrade your exercism command-line client"
          end
          data['language'] = segments[0]
          data['problem'] = segments[1]
          data['path'] = segments[2..-1].join("/")
        end

        iteration = Iteration.new(
          solution,
          data['language'],
          data['problem'],
          comment: data['comment']
        )
        attempt = Attempt.new(user, iteration)

        unless attempt.valid?
          error = "unknown problem (track: %s, slug: %s, path: %s)" % [
            attempt.track,
            attempt.slug,
            data['path'],
          ]
          halt 400, { error: error }.to_json
        end

        if attempt.duplicate?
          halt 400, { error: "duplicate of previous iteration" }.to_json
        end

        attempt.save

        ACL.authorize(user, attempt.submission.problem)

        Notify.everyone(attempt.submission.reload, 'iteration', user)

        ConversationSubscription.join(user, attempt.submission)

        if (attempt.track == 'ruby' && attempt.slug == 'hamming') || attempt.track == 'go'
          Jobs::Analyze.perform_async(attempt.submission.key)
        end
        if attempt.slug == 'hello-world'
          Jobs::Hello.perform_async(attempt.submission.key, attempt.submission.version)
        end

        status 201
        locals = {
          submission: attempt.submission,
          domain: request.url.gsub(/#{request.path}$/, "")
        }
        pg :attempt, locals: locals
      end

      # Restore solutions.
      # Called from XAPI.
      get '/iterations/latest' do
        require_key

        if current_user.guest?
          message = "Please double-check your exercism API key."
          halt 401, { error: message }.to_json
        end

        exercises = current_user.exercises.order(:language, :slug)

        submissions = exercises.map { |e| e.submissions.last }.compact

        pg :iterations, locals: {submissions: submissions}
      end
    end
  end
  # rubocop:enable Metrics/ClassLength
end
