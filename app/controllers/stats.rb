Dandelion::App.controller do
  before do
    admins_only!
  end

  get '/stats/events' do
    erb :'stats/events'
  end

  get '/stats/feedback' do
    @event_feedbacks = EventFeedback.order('created_at desc')
    erb :'stats/feedback'
  end

  get '/stats/orders' do
    @orders = Order.order('created_at desc')
    erb :'stats/orders'
  end

  get '/stats/organisations' do
    erb :'stats/organisations'
  end

  get '/stats/places' do
    @places = Place.order('created_at desc').paginate(page: params[:page], per_page: 50)
    erb :'stats/places'
  end

  get '/stats/comments' do
    @comments = Comment.and(:body.ne => nil).order('created_at desc').paginate(page: params[:page], per_page: 20)
    erb :'stats/comments'
  end

  get '/stats/accounts' do
    @accounts = Account.public.order('created_at desc').and(ps_account_id: nil).paginate(page: params[:page], per_page: 20)
    erb :'stats/accounts'
  end

  get '/stats/messages' do
    @messages = Message.order('created_at desc').paginate(page: params[:page], per_page: 20)
    erb :'stats/messages'
  end
end
