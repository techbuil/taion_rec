require 'oauth'
require 'json'
require "time"
require 'csv'
require 'gnuplot'
require 'twitter'

# 最大のプロット数
Max_Point_Const = 240
Max_Point_Const.freeze

# 生理の最大表示数
Max_Seiri_Const = 8
Max_Seiri_Const.freeze

# 1画像あたりのグラフ表示数
Max_Graph_Const = 2
Max_Graph_Const.freeze

# 画像枚数の最大数
Max_Pic_Const = 4
Max_Pic_Const.freeze

# Twitter認証用の鍵
Consumer_Key_Const = '***'
Consumer_Secret_Const = '***'
Access_Token_Const = '***'
Access_Token_Secret_Const = '***'

#json用のリクエストトークン発行（require 'oauth'）
def make_request_token()
  consumer_key = Consumer_Key_Const.to_s
  consumer_secret = Consumer_Secret_Const.to_s
  access_token = Access_Token_Const.to_s
  access_token_secret = Access_Token_Secret_Const.to_s

  consumer = OAuth::Consumer.new(consumer_key, consumer_secret, site:'https://api.twitter.com')
  request_token = OAuth::AccessToken.new(consumer, access_token, access_token_secret)
  return request_token
end


def json_req( request_token, last_id )
  response_url = 'https://api.twitter.com/1.1/statuses/mentions_timeline.json?&since_id='.to_s + last_id.to_s
  response =  request_token.get( response_url )
  result = JSON.parse(response.body)
  return result
end


def last_id_read()
  last_id = []
  File.open("last_id.txt", "rt") do |f|
    last_id = f.readlines
  end
  return last_id[0].chomp
end

# p_userid=ユーザー個別ID(数字); user_name=スクリーンネーム（人によっては日本語かもしれない）
# gnuplot_png()の返り値は生成した枚数
def gnuplot_png(p_userid, user_name)
  # 高々Max_Point_Constに押さえこむ前の日付と体温を入れておく配列
  days = []
  taion = []

  # plotのために大きめの二次元配列を用意する
  # なんとかならなければ、工夫する必要がある
  # gnuplot用カラム分け番号を振るのも悪手だとは思うが、配列構造の複雑化を避けるためにこのようにした
  # [0]:gnuplot用年月, [1]:体温, [2]:gp用カラム分け番号
  plot_column = Array.new(3).map{Array.new(Max_Point_Const, nil)}

  csv_path = './csv/'.to_s + p_userid.to_s + '.csv'.to_s

  # [ [2018-5-29;23:25:59,36.01], [2018-5-30;23:25:59,36.01],...]
  taion_csv = CSV.read("#{csv_path}")
  taion_csv.each do |row|
    days << row[0]
    taion << row[1]
  end

  # arr_inputの要素数がnを超えていたら（nを含まない）、後方のn個のみの配列arr_kekkaを返す
  # 要素数がn以下(nを含む)の場合、何もしないでarr_inputを返す
  def takadaka(n, arr_input)
    if arr_input.length > n
      kekka =  arr_input.last(n)
      return kekka
    else
      return arr_input
    end
  end


  # plot数を直近の高々max_pointに押さえこむ
  # [0]:gnuplot用年月, [1]:体温, [2]:gp用カラム分け番号
  plot_column[0] = takadaka(Max_Point_Const, days)
  plot_column[1] = takadaka(Max_Point_Const, taion)


  # 生理ファイルの有無を確認して、あれば読み込む
  # なければseiri_hantei == falseのフラグを立てておく


  csv_path_seiri = './csv/'.to_s + p_userid.to_s + '_seiri'.to_s + '.csv'.to_s
  seiri_hantei = File.exist?( "#{csv_path_seiri}" )
  seiri_days = []
  if seiri_hantei
    File.open("#{csv_path_seiri}") do |file|
      file.each_line do |each_l|
        seiri_days << each_l.chomp
      end
    end
  end


  # 生理の回数を直近の高々Max_Seiri_Const回に押さえこむ
  if seiri_hantei
    seiri_days = takadaka( Max_Seiri_Const, seiri_days )
  end


  # 日付と分割日から、gnuplotのカラムを決定する配列を返す
  # hiduke = plot_column[0], bunkatu = seiri_days
  # [0]:gnuplot用年月, [1]:体温, [2]:gp用カラム分け番号
  def gp_column_seisei(hiduke, bunkatu)
    # gnuplot用の日付(配列)からRubyの日付型（配列）を返す
    def hiduke_rubify(h_g)
      hiduke_result = []
      h_g.each do |h|
        # 配列型が間違えて降ってくることがあるので、愚直にString型に変換する
        # （おそらく改行コードの問題だが深く追求していない）
        if h.instance_of?(Array)
          h_temp = ""
          h_temp = h[0].to_s
          h = ""
          h = h_temp
        end
        # ここには体温情報、生理情報のCSVが行ごとにそのまま流れてくるので
        # 体温情報があれば消す（消さないとstrptimeがエラー起こす）
        h.to_s.gsub!(/\,\d\d\.\d\d/, "")
        if not h == nil
          hiduke_result << Time.strptime(h.to_s, "%Y-%m-%d;%H:%M:%S")
        else
          hiduke_result << nil
        end
      end
      return hiduke_result
    end


    hiduke_ruby = []
    bunkatu_ruby = [] 
    hiduke_ruby = hiduke_rubify(hiduke)
    bunkatu_ruby = hiduke_rubify(bunkatu)


    column_kekka = []

    column_max = Max_Graph_Const.to_i * Max_Pic_Const.to_i

    # 分割指示がnilのときは、hiduke_ruby分の0が入った配列を返す（生理がないときは全て0列目のグラフの意）
    if bunkatu_ruby[0] == nil
      (0..hiduke.length).each do |i|
        column_kekka[i] = 1
      end
    else
      # 分割指示があるときは、日付を比較して適切なカラムを指定する
      count = 1
      hiduke_ruby.each do |hiduke_r|
        if count <= column_max and ( not hiduke_r == nil ) 
          # 分割日以前のデータ
          if hiduke_r < bunkatu_ruby[count-1]
            column_kekka << count
          # 分割日以後のデータで、次の分割日がないもの（countをインクリしてしまうと次のデータで空振る）
          elsif bunkatu_ruby[count] == nil
            j = count.to_i + 1.to_i
            column_kekka << j
          # 分割日以後のデータで、次の分割日があるもの
          else
            count = count.to_i + 1
            column_kekka << count
          end
        # countがカラムの上限を超えたときや、日付がnilのときはカラムをnilにしてプロットの対象外にする
        else
          column_kekka << nil
        end
      end #each終
    end
    return column_kekka
  end
  # gp_column_seisei終

  # [0]:gnuplot用年月, [1]:体温, [2]:gp用カラム分け番号
  plot_column[2] = gp_column_seisei(plot_column[0], seiri_days)



  column_saidai = plot_column[2].max

  max_graph = Max_Graph_Const
  maisu = (column_saidai.to_f / max_graph.to_f).ceil

  if maisu > Max_Pic_Const
    maisu = Max_Pic_Const
  end

  # pngをmaisu枚生成する
  (1..maisu).each do |maisu_count|
    Gnuplot.open do |gp|
      Gnuplot::Plot.new(gp) do |plot|
        plot.xlabel "日付"
        plot.ylabel "体温"
        plot.timefmt "'%Y-%m-%d;%H:%M:%S'"
        plot.xdata "time"
        plot.format "x '%m-%d'"
        plot.style "data lines"
        plot.output "./png/#{p_userid}_#{maisu_count}.png"
        plot.title "#{user_name} さんの基礎体温表"
        plot.set 'terminal pngcairo enhanced size 1280,960 font "SetoFont,20"'
        plot.set 'format y "%4.2f"'
        plot.key 'box linestyle 1'
        plot.key 'left top'




        # [0]:gnuplot用年月, [1]:体温, [2]:gp用カラム分け番号
        if column_kokomade > plot_column[2].max
          column_kokomade = plot_column[2].max
        end


        column_kokokara = Max_Graph_Const * (maisu_count - 1) + 1
        column_kokomade = column_kokokara + Max_Graph_Const - 1

        (column_kokokara..column_kokomade).each do |i|
          # 分割後のデータを一時保存し、gnuplotに順番に食べさせる用の配列を生成している
          # 全探索をかけているので処理が遅いが、サンプル数が少ないのでなんとかなっている
          # 要素の個数をもとに配列を分割する、カラム番号を振るのをやめて直接配列分割をする等の工夫をすると速いかもしれない
          # [0]:gnuplot用年月, [1]:体温, [2]:gp用カラム分け番号
          plot_day = []
          plot_taion = []
          plot_column[0].zip(plot_column[1],plot_column[2]) do |h, t, c|
            if c == i
              plot_day << h
              plot_taion << t
            end
          end

          h = Time.strptime(plot_day[0], "%Y-%m-%d;%H:%M:%S")
          o = Time.strptime(plot_day[plot_day.length.to_i-1], "%Y-%m-%d;%H:%M:%S")
          hajime = h.year.to_s + "年".to_s + h.month.to_s + "月".to_s + h.day.to_s +  "日"
          owari  = o.year.to_s + "年".to_s + o.month.to_s + "月".to_s + o.day.to_s +  "日"
          # 計測期間
          kankaku = ((o - h).to_f / (24*60*60).to_f).round(2)
          # 小数点以下が0.75以上のとき（体温計測時間の誤差6時間(1/4日)）は、一日増やす処理をする
          kankaku_sho = kankaku.to_f - kankaku.floor.to_f
          if kankaku_sho.to_f > 0.75
            kankaku = kankaku.to_f + 1.0
          end
          kankaku = kankaku.ceil

          # グラフ本体と凡例
          plot.data << Gnuplot::DataSet.new([plot_day, plot_taion]) do |ds|
            ds.with      = "linespoints"
            ds.linewidth = 2
            ds.linecolor = 2 + i
            ds.title = hajime.to_s + "から".to_s + owari.to_s + "(".to_s + kankaku.to_s + "日間)".to_s
            ds.using = "1:2"
          end
        end
      end
    end
  end
  return maisu
end




# jsonを使った画像のアップロードが困難だったので、画像をアップロードする必要がある処理はAPIを使う（require 'twitter'）
# jsonの部分もAPIに投げられるはずだが、jsonのほうがデータが細かいので暫定的にそのままにしている
# そのため、合計2回トークンを発行する仕様になっている（あまり行儀が良い仕様とは言えない）
# p=user個別ID(数字); s=発言の個別ID（数字） ; n=@の名前
def pic_upload(p, s, n, maisu)

  twitter_client = Twitter::REST::Client.new do |config|
    config.consumer_key       = Consumer_Key_Const.to_s
    config.consumer_secret    = Consumer_Secret_Const.to_s
    config.access_token        = Access_Token_Const.to_s
    config.access_token_secret = Access_Token_Secret_Const.to_s
  end

  media_files = []
  (1..maisu).each do |i|
    media_files << "./png/#{p}_#{i}.png"
  end

  naiyo = "@".to_s + n.to_s + " ".to_s + "基礎体温のグラフを貼っておくよ！神秘だね！！！！".to_s
  twitter_client.update_with_media( naiyo.to_s, media_files , { :in_reply_to_status_id => s.to_i } )

end

# ユーザーのCSVの最後にデータを付け加える手続き(u:ユーザーID ,j:時刻, t:体温)
# 体温 == nilで生理データと判定
def add_csv(u, j, t)
  # output_lineはCSVに追記するデータ
  output_line = []

  csv_path = []
  # dにはstrptimeされた時刻の配列が入る
  d = Time.new
  if t == nil
    # 生理の時間と判定
    d = Time.strptime(j, "%a %b %d %H:%M:%S %z %Y").getlocal("+09:00").to_a
    # 一発言で生理と体温が来た時にも、生理が確実に前に来るように、予め5分引いておく場合、下行を加えるとよい
    # d = d.ago(5.minutes).to_s
    output_line = d[5].to_s + '-'.to_s + d[4].to_s + '-'.to_s + d[3].to_s + ';' + d[2].to_s + ':'.to_s + d[1].to_s + ':'.to_s + d[0].to_s
    csv_path = './csv/'.to_s + u.to_s + "_seiri".to_s + '.csv'.to_s
  elsif
    # 体温データと判定
    d = Time.strptime(j, "%a %b %d %H:%M:%S %z %Y").getlocal("+09:00").to_a
    output_line = d[5].to_s + '-'.to_s + d[4].to_s + '-'.to_s + d[3].to_s + ';' + d[2].to_s + ':'.to_s + d[1].to_s + ':'.to_s + d[0].to_s + ',' + t.to_s
    csv_path = './csv/'.to_s + u.to_s + '.csv'.to_s
  end
  File.open( "#{csv_path}", "a") do |f|
    f.puts( output_line )
  end
end


# 生理情報を得たときのレス返し。JSONを使っている
#「生理」という文字列を含めてしまうと自レスが次回の処理で正規表現にマッチしてしまい誤爆の元になるので、「アレ」とした
# s:つぶやきの固有ID（数字）, n:ユーザーの@名前, h:ユーザーの名前（日本語含む可能性あるほう）
def seiri_hatugen(s, n, h, request_token)
  naiyo = "@".to_s + n.to_s + " ".to_s + h.to_s + "ちゃんのアレな情報を記録しておいたよ！！！".to_s
  request_token.post('https://api.twitter.com/1.1/statuses/update.json', in_reply_to_status_id: s.to_s, status: naiyo.to_s)
end



# ここからmain関数

last_id = last_id_read()
last_id_kouho = last_id

# jsonのリクエストトークン
request_token = make_request_token()

# last_id以降のつぶやきをparseしたもの
result = json_req( request_token, last_id )

# TwitterのJSON返り値の仕様：
# tweet['user']['id_str']     -> ユーザー固有の数字ID（数字）
# tweet['id_str']             -> つぶやきの固有ID（数字）
# tweet['user']['screen_name']-> ユーザーの@名前
# tweet['user']['name'].to_s  -> ユーザーの名前（日本語含む可能性あるほう）

result.each do |tweet|
  # 体温向けの処理
  if taion = tweet['text'].match(/\d\d\.\d\d/)
    add_csv(tweet['user']['id_str'].to_s, tweet['created_at'], taion)
    # 体温が入っていたとき、ユーザー毎のグラフをpngで出力、保存し（gnuplot_png）、
    # それらをTwitterのレスとしてアップロードする（pic_upload）
    seisei_maisu = gnuplot_png(tweet['user']['id_str'].to_s, tweet['user']['name'].to_s)
    pic_upload(tweet['user']['id_str'].to_s, tweet['id_str'].to_s, tweet['user']['screen_name'].to_s, seisei_maisu)
  end
  # 生理向けの処理。CSVの末尾に日時を記録し（add_csv）、レス返し（seiri_hatugen）
  if tweet['text'].match(/生理/)
    add_csv(tweet['user']['id_str'].to_s, tweet['created_at'], nil)
    seiri_hatugen(tweet['id_str'].to_s, tweet['user']['screen_name'].to_s, tweet['user']['name'].to_s, request_token)
  end
  # 取得したつぶやき（自分へのレス）のうちIDの最大数を取得する。
  # もっとも、現在の仕様では取得したJSONの一番初めのものが最大のIDとなるようだが、誤動作防止のため一応確認させている
  if tweet['id_str'] > last_id_kouho
    last_id_kouho = tweet['id_str']
  end
end


if last_id_kouho.to_i > last_id.to_i
  File.open("last_id.txt", "w") do |f|
    f.puts( last_id_kouho )
  end
end
