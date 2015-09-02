module ExercismWeb
  module Routes
    class Submissions < Core
      get '/submissions/:key' do |key|
        submission = Submission.includes(:user, comments: :user).find_by_key(key)
        unless submission
          flash[:error] = "We can't find that submission."
          redirect '/'
        end

        if current_user.guest?
          workload = NullWorkload.new
        else
          submission.viewed!(current_user)
          Look.check!(submission.user_exercise_id, current_user.id)
          Notification.viewed!(submission, current_user)
          workload = Workload.new(current_user, submission.track_id, submission.slug)
        end
        next_submission = workload.next_submission(submission)

        title("%s by %s in %s" % [submission.problem.name, submission.user.username, submission.problem.language])

        erb :"submissions/show", locals: {submission: submission, next_submission: next_submission, sharing: Sharing.new}
      end

      post '/submissions/:key/like' do |key|
        please_login "You have to be logged in to do that."
        submission = Submission.find_by_key(key)
        if submission.nil?
          flash[:notice] = "No such exercise found"
          redirect "/"
        end

        submission.like!(current_user)
        Notify.source(submission, 'like', current_user)
        redirect "/submissions/#{key}"
      end

      # Provide unlike, mute, and unmute actions.
      {
        "unlike" => "The submission has been unliked.",
        "mute" => "The submission has been muted. It will reappear when there has been some activity.",
        "unmute" => "The submission has been unmuted."
      }.each do |action, confirmation|
        post "/submissions/:key/#{action}" do |key|
          please_login "You have to be logged in to do that."
          submission = Submission.find_by_key(key)
          submission.send("#{action}!", current_user)
          flash[:notice] = confirmation
          redirect "/submissions/#{key}"
        end
      end

      get %r{/submissions/(?<key>\w+)/(nitpick$|(\+?un)?like$|(\+?un)?mute$)} do |key|
        redirect "/submissions/#{key}"
      end

      post '/submissions/:key/done' do |key|
        please_login("You have to be logged in to do that")
        submission = Submission.find_by_key(key)
        unless current_user.owns?(submission)
          flash[:notice] = "Only the author may complete the exercise."
          redirect "/submissions/#{key}"
        end
        Completion.new(submission).save
        LifecycleEvent.track('completed', current_user.id)
        flash[:success] = "#{submission.name} in #{submission.track_id} will no longer appear in the nitpick lists."
        redirect "/"
      end

      post '/submissions/:key/reopen' do |key|
        please_login
        selected_submission = Submission.find_by_key(key)
        unless current_user.owns?(selected_submission)
          flash[:notice] = "Only the current author may reopen the exercise"
          redirect '/'
        end

        submission = Submission.where(user_id: current_user.id, language: selected_submission.track_id, slug: selected_submission.slug, state: 'done').first

        if submission.nil?
          flash[:notice] = "No such submission"
          redirect "/"
        end

        submission.state = 'pending'
        submission.done_at = nil
        submission.save
        Hack::UpdatesUserExercise.new(submission.user_id, submission.track_id, submission.slug).update
        redirect "/submissions/#{submission.key}"
      end

      post '/submissions/:key/hibernate' do |key|
        please_login("You have to be logged in to do that")
        submission = Submission.find_by_key(key).participant_submissions.last
        unless current_user.owns?(submission)
          flash[:notice] = "Only the author may hibernate this exercise."
          redirect "/submissions/#{key}"
        end
        submission.state = "hibernating"
        submission.save
        Hack::UpdatesUserExercise.new(submission.user_id, submission.track_id, submission.slug).update
        flash[:success] = "#{submission.name} in #{submission.track_id} is now hibernating."
        redirect "/"
      end

      post '/submissions/:key/wakeup' do |key|
        submission = Submission.find_by_key(key)
        unless current_user.owns?(submission)
          flash[:notice] = "Only the author may reactivate the exercise."
          redirect "/submissions/#{key}"
        end
        submission.user_exercise.reopen!
        flash[:success] = "#{submission.name} in #{submission.track_id} is now active."
        redirect '/'
      end

      delete '/submissions/:key' do |key|
        please_login
        submission = Submission.find_by_key(key)
        if submission.nil?
          redirect '/'
        end

        unless current_user.owns?(submission)
          flash[:notice] = "Only the author may delete the exercise."
          redirect '/'
        end

        decrement_version(submission)
        prior = submission.prior
        if prior && (submission.state == 'pending')
          prior.state = 'pending'
          prior.save
        end
        submission.destroy
        Hack::UpdatesUserExercise.new(submission.user_id, submission.track_id, submission.slug).update
        redirect "/"
      end
    end
  end
end