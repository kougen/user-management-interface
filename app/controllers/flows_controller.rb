class FlowsController < ApplicationController

  def registration
    flow_id = params[:flow]
    fetch_flow(flow_id, "registration", registration_path)
  end

  def registration_submit
    form_data = params
    handle_submit(form_data, "registration", :registration)
  end

  def login
    flow_id = params[:flow]
    fetch_flow(flow_id, "login", login_path)
  end

  def login_submit
    form_data = params
    handle_submit(form_data, "login", :login)
  end

  def errors
    error_id = params[:id]
    full = "#{ENV['KRATOS_PUBLIC_URL']}/self-service/errors?id=#{error_id}"
    response = get(full)
    @flow_type = "registration"
    @error = JSON.pretty_generate(response.parse)
  end

  private

  def fetch_flow(flow_id, flow_type, submit_path = nil)
    kratos_url = ENV['KRATOS_PUBLIC_URL']
    if flow_id
      full_url = "#{kratos_url}/self-service/#{flow_type}/flows?id=#{flow_id}"
      response = get(full_url)
      if response.status == 410
        @error = JSON.pretty_generate(response.parse)
        @flow_type = flow_type
        render :errors
        return
      end
      if response.status == 400
        redirect_to "/#{flow_type}?flow=#{response.parse["id"]}"
        return
      end

      if response.status == 303
        redirect_to response.headers["Location"]
        return
      end
      @submit_path = submit_path
      @flow = response.parse
      return
    end

    full_url = "#{kratos_url}/self-service/#{flow_type}/browser?"
    response = get(full_url)
    set_cookie(response)
    redirect = response.headers["Location"] || "/#{flow_type}?flow=#{response.parse["id"]}"
    redirect_to redirect
  end

  def handle_submit(form_data, flow_type, render_path)
    action_url = form_data["action_url"]
    response = post(action_url, form_data)
    if response.status == 200
      set_cookie(response)
      redirect_to root_path
    elsif response.status == 400
      redirect_to "/#{flow_type}?flow=#{response.parse["id"]}"
    elsif response.status == 422
      url = response.parse["redirect_browser_to"]
      set_cookie(response)
      @redirect_url = url
      render render_path, :status => 422
    elsif response.status == 303
      redirect_to response.headers["Location"]
    else
      @error = JSON.pretty_generate(response.parse)
      @flow_type = flow_type
    end
  end

  def set_cookie(response)
    response_headers = response.headers
    set_cookies = response_headers["Set-Cookie"]
    return unless set_cookies
    _set_cookies = []
    if set_cookies.is_a?(String)
      _set_cookies << set_cookies
    else
      _set_cookies = set_cookies
    end

    _set_cookies.each do |set_cookie|
      cookie = set_cookie.split(";")
      cookie_name = cookie[0].split("=")[0]
      cookie_value = cookie[0].split("=", 2)[1]
      path = get_property_from_cookie(cookie, "Path")
      max_age = get_property_from_cookie(cookie, "Max-Age")
      max_age = max_age.to_i if max_age
      http_only = get_property_from_cookie(cookie, "HttpOnly", true)
      http_only = http_only != nil

      cookie_options = {}
      cookie_options[:path] = path if path
      cookie_options[:max_age] = Time.now + max_age if max_age
      cookie_options[:http_only] = http_only if http_only
      cookie_options[:value] = cookie_value
      cookie_name_sym = cookie_name.to_sym
      cookies[cookie_name_sym] = cookie_options
    end
  end

  def get_property_from_cookie(cookie, property, only_present = false)
    cookie.each do |c|
      if c.include?(property)
        if only_present
          return true
        end
        return c.split("=")[1]
      end
    end
    nil
  end

  def get_ui_nodes(body)
    JSON.parse(body)["ui"]["nodes"]
  end

  def get(url)
    cookie_string = cookies.map { |k, v| "#{k}=#{v}" }.join("; ")
    HTTP.headers("Cookie" => cookie_string)
        .headers(:accept => "application/json")
        .get(url)
  end

  def post(url, body)
    HTTP
      .headers("Content-Type" => "application/json")
      .headers("X-Forwarded-For" => request.remote_ip)
      .headers("User-Agent" => request.user_agent)
      .headers("Cookie" => cookies.map { |k, v| "#{k}=#{v}" }.join("; "))
      .post(url, :json => body)
  end

end
