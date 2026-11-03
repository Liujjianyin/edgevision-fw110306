using System;
using System.Drawing;
using System.IO;
using System.IO.Ports;
using System.Collections.Generic;
using System.Text;
using System.Windows.Forms;
using System.Diagnostics;
namespace EdgeVisionControl {
 public sealed class StudioButton:Button {
  protected override void OnPaint(PaintEventArgs e){
   if(Enabled){base.OnPaint(e);return;}
   e.Graphics.Clear(Color.FromArgb(29,43,61));
   using(var pen=new Pen(Color.FromArgb(53,70,90)))e.Graphics.DrawRectangle(pen,0,0,Width-1,Height-1);
   TextRenderer.DrawText(e.Graphics,Text,Font,ClientRectangle,Color.FromArgb(137,154,175),TextFormatFlags.HorizontalCenter|TextFormatFlags.VerticalCenter);
  }
 }
 public sealed class MainForm:Form {
  sealed class LayoutBase {public Rectangle Bounds;public Padding Margin,Padding;public Font Font;}
  sealed class RowBase {public SizeType Type;public float Height;}
  readonly Color bg=Color.FromArgb(11,18,32),card=Color.FromArgb(21,32,50),line=Color.FromArgb(43,60,81);
  readonly Color cyan=Color.FromArgb(70,218,220),ink=Color.FromArgb(237,244,253),muted=Color.FromArgb(150,170,195);
  readonly Color green=Color.FromArgb(106,229,172),amber=Color.FromArgb(255,198,98);
  readonly FrameDecoder decoder=new FrameDecoder();readonly BoardState board=new BoardState();
  readonly List<Button> actionButtons=new List<Button>();readonly Label[] slotState=new Label[3];
  readonly List<Button> videoButtons=new List<Button>();Button displayButton,thresholdUpButton,thresholdDownButton,algorithmButton,medianButton,detectionButton,backgroundButton;Label detectionStatus;int calibrationBefore;
  readonly Button[] saveButtons=new Button[3],showButtons=new Button[3];readonly Timer poll=new Timer{Interval=40};
  SerialPort port;ComboBox ports;Button connect,refresh,record,play,resume,clear;
  Label connection,mode,health,writeCount,readCount,operation,videoState,progress,footer,processingStatus;TextBox log;StreamWriter logfile;
  DateTime lastQuery=DateTime.MinValue,opened,sent,videoSent;byte? pending,pendingVideoCommand;string pendingName,pendingVideoName;ushort pendingVideoThreshold;bool accepted,wasFresh;
  DateTime lastWriteChange=DateTime.MinValue,lastDiagnosticLog=DateTime.MinValue;bool writeStalled;
  int lastState=-1,lastFlags=-1;
  string lastLinkSummary="";
  TableLayoutPanel rootLayout;readonly Dictionary<Control,LayoutBase> layoutBases=new Dictionary<Control,LayoutBase>();readonly Dictionary<string,Font> scaledFonts=new Dictionary<string,Font>();RowBase[] rootRows;Size baseClientSize;bool responsiveReady;float appliedScale=1f;
  public MainForm(){
   Text="EdgeVision Studio · 四种饮料识别 / HDMI / DDR · 110306";Size=new Size(1180,850);MinimumSize=new Size(1040,780);
   StartPosition=FormStartPosition.CenterScreen;BackColor=bg;ForeColor=ink;Font=new Font("Microsoft YaHei UI",9F);AutoScaleMode=AutoScaleMode.Dpi;
   rootLayout=new TableLayoutPanel{Dock=DockStyle.Fill,Padding=new Padding(22,16,22,16),ColumnCount=1,RowCount=7};
   foreach(int h in new[]{76,64,98,54,230,164})rootLayout.RowStyles.Add(new RowStyle(SizeType.Absolute,h));
   rootLayout.RowStyles.Add(new RowStyle(SizeType.Percent,100));Controls.Add(rootLayout);
   rootLayout.Controls.Add(Header(),0,0);rootLayout.Controls.Add(ConnectionBar(),0,1);rootLayout.Controls.Add(StatusRow(),0,2);
   operation=Label("连接开发板后，状态将由 FPGA 实时回传。",11,muted);operation.Dock=DockStyle.Fill;operation.TextAlign=ContentAlignment.MiddleLeft;rootLayout.Controls.Add(operation,0,3);
   rootLayout.Controls.Add(Actions(),0,4);rootLayout.Controls.Add(Slots(),0,5);rootLayout.Controls.Add(LogPanel(),0,6);
   poll.Tick+=Poll;poll.Start();Shown+=delegate{RefreshPorts();OpenLog();Log("控制台就绪。固定 115200 / 8N1；连接时仅发送查询。");UpdateView();CaptureResponsiveLayout();};
   Resize+=delegate{if(responsiveReady)ApplyResponsiveLayout();};
   FormClosing+=delegate{poll.Stop();Disconnect();if(logfile!=null)logfile.Dispose();};
  }
  void CaptureControlLayout(Control c){layoutBases[c]=new LayoutBase{Bounds=c.Bounds,Margin=c.Margin,Padding=c.Padding,Font=c.Font};foreach(Control child in c.Controls)CaptureControlLayout(child);}
  void CaptureResponsiveLayout(){if(responsiveReady)return;baseClientSize=ClientSize;rootRows=new RowBase[rootLayout.RowStyles.Count];for(int i=0;i<rootRows.Length;i++)rootRows[i]=new RowBase{Type=rootLayout.RowStyles[i].SizeType,Height=rootLayout.RowStyles[i].Height};CaptureControlLayout(this);responsiveReady=true;ApplyResponsiveLayout();}
  static int ScaleValue(int value,float scale){return (int)Math.Round(value*scale);}
  static Padding ScalePadding(Padding value,float scale){return new Padding(ScaleValue(value.Left,scale),ScaleValue(value.Top,scale),ScaleValue(value.Right,scale),ScaleValue(value.Bottom,scale));}
  Font ScaledFont(Font source,float scale){int eighths=(int)Math.Round(source.Size*scale*8);string key=source.Name+"|"+source.Style+"|"+source.Unit+"|"+source.GdiCharSet+"|"+source.GdiVerticalFont+"|"+eighths;Font result;if(!scaledFonts.TryGetValue(key,out result)){result=new Font(source.FontFamily,Math.Max(8f,eighths/8f),source.Style,source.Unit,source.GdiCharSet,source.GdiVerticalFont);scaledFonts.Add(key,result);}return result;}
  void ApplyResponsiveLayout(){
   if(!responsiveReady||baseClientSize.Width<=0||baseClientSize.Height<=0)return;
   float scale=Math.Min(1.80f,Math.Max(1f,Math.Min(ClientSize.Width/(float)baseClientSize.Width,ClientSize.Height/(float)baseClientSize.Height)));
   if(Math.Abs(scale-appliedScale)<0.015f)return;
   SuspendLayout();rootLayout.SuspendLayout();rootLayout.Padding=ScalePadding(layoutBases[rootLayout].Padding,scale);
   for(int i=0;i<rootRows.Length;i++)if(rootRows[i].Type==SizeType.Absolute)rootLayout.RowStyles[i].Height=rootRows[i].Height*scale;
   foreach(KeyValuePair<Control,LayoutBase> entry in layoutBases){Control c=entry.Key;LayoutBase b=entry.Value;if(c==this||c==rootLayout||c.IsDisposed)continue;
    c.Margin=ScalePadding(b.Margin,scale);c.Padding=ScalePadding(b.Padding,scale);
    if(c.Dock==DockStyle.None)c.SetBounds(ScaleValue(b.Bounds.X,scale),ScaleValue(b.Bounds.Y,scale),Math.Max(1,ScaleValue(b.Bounds.Width,scale)),Math.Max(1,ScaleValue(b.Bounds.Height,scale)));
    else if(c.Dock==DockStyle.Left||c.Dock==DockStyle.Right)c.Width=Math.Max(1,ScaleValue(b.Bounds.Width,scale));
    else if(c.Dock==DockStyle.Top||c.Dock==DockStyle.Bottom)c.Height=Math.Max(1,ScaleValue(b.Bounds.Height,scale));
    if(b.Font!=null)c.Font=ScaledFont(b.Font,scale);
   }
   Font baseFormFont=layoutBases[this].Font;if(baseFormFont!=null)Font=ScaledFont(baseFormFont,scale);
   appliedScale=scale;rootLayout.ResumeLayout(true);ResumeLayout(true);
  }
  Label Label(string text,float size,Color color){return new Label{Text=text,ForeColor=color,Font=new Font("Microsoft YaHei UI",size),AutoSize=false,Margin=new Padding(0),AutoEllipsis=true};}
  Panel Card(){var p=new Panel{Dock=DockStyle.Fill,BackColor=card,Margin=new Padding(0,0,10,8)};p.Paint+=delegate(object s,PaintEventArgs e){using(var pen=new Pen(line))e.Graphics.DrawRectangle(pen,0,0,p.Width-1,p.Height-1);};return p;}
  TableLayoutPanel Columns(int n){var t=new TableLayoutPanel{Dock=DockStyle.Fill,ColumnCount=n,RowCount=1,Margin=new Padding(0)};for(int i=0;i<n;i++)t.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,100F/n));return t;}
  Button Button(string text,EventHandler click,bool primary=false){
   var b=new StudioButton{Text=text,Height=36,Width=128,FlatStyle=FlatStyle.Flat,BackColor=primary?Color.FromArgb(23,112,133):Color.FromArgb(34,51,74),ForeColor=ink,Cursor=Cursors.Hand,Margin=new Padding(0,0,8,0)};
   b.FlatAppearance.BorderColor=primary?cyan:line;b.FlatAppearance.BorderSize=1;b.Click+=click;return b;
  }
  Button Action(string text,byte command,string name,bool primary=false){var b=Button(text,delegate{Send(command,name);},primary);actionButtons.Add(b);return b;}
  Button VideoAction(string text,Action click){var b=Button(text,delegate{click();});b.Width=88;videoButtons.Add(b);return b;}
  Control Header(){
   var p=new Panel{Dock=DockStyle.Fill,Margin=new Padding(0)};var title=Label("EDGEVISION  /  STUDIO",23,ink);title.Font=new Font("Segoe UI",23,FontStyle.Bold);title.SetBounds(0,0,600,42);
   var sub=Label("Ti60F225  ·  饮料识别 / Sobel / Canny / 中值 / DDR",10,muted);sub.SetBounds(2,46,620,24);
   var tag=Label("1080p60fps  /  CNN 演示",10,cyan);tag.TextAlign=ContentAlignment.MiddleRight;tag.Dock=DockStyle.Right;tag.Width=320;p.Controls.Add(title);p.Controls.Add(sub);p.Controls.Add(tag);return p;
  }
  Control ConnectionBar(){
   var p=Card();p.Padding=new Padding(14,10,14,10);var row=new FlowLayoutPanel{Dock=DockStyle.Fill,WrapContents=false,Margin=new Padding(0)};
   var l=Label("设备",10,muted);l.Size=new Size(44,32);l.TextAlign=ContentAlignment.MiddleLeft;row.Controls.Add(l);
   ports=new ComboBox{DropDownStyle=ComboBoxStyle.DropDownList,Width=106,BackColor=card,ForeColor=ink,FlatStyle=FlatStyle.Flat,Margin=new Padding(0,4,12,0)};row.Controls.Add(ports);
   var rate=Label("115200 · 8N1",10,muted);rate.Size=new Size(130,34);rate.TextAlign=ContentAlignment.MiddleLeft;row.Controls.Add(rate);
   refresh=Button("刷新设备",delegate{RefreshPorts();});refresh.Width=94;row.Controls.Add(refresh);
   connect=Button("连接设备",delegate{if(port==null)Connect();else Disconnect();},true);connect.Width=108;row.Controls.Add(connect);
   connection=Label("●  未连接",10,muted);connection.Size=new Size(400,34);connection.TextAlign=ContentAlignment.MiddleLeft;connection.Margin=new Padding(10,0,0,0);row.Controls.Add(connection);p.Controls.Add(row);return p;
  }
  Control StatusRow(){
   var t=Columns(4);string[] names={"DDR / 当前模式","链路健康","DDR 写帧计数","DDR 读帧计数"};Label[] labels=new Label[4];
   for(int i=0;i<4;i++){var p=Card();var a=Label(names[i],9,muted);a.SetBounds(14,10,230,23);p.Controls.Add(a);
    var b=Label("—",16,ink);b.SetBounds(14,34,230,32);b.Anchor=AnchorStyles.Left|AnchorStyles.Top|AnchorStyles.Right;p.Controls.Add(b);labels[i]=b;
    var note=Label(i>=2?"8 位计数 · 到 255 回绕":i==1?"DDR 校准 / 输入锁定 / 帧稳定":"以实体板状态为准",8,muted);note.SetBounds(14,68,230,18);p.Controls.Add(note);t.Controls.Add(p,i,0);
   }mode=labels[0];health=labels[1];health.Font=new Font("Microsoft YaHei UI",11);writeCount=labels[2];readCount=labels[3];return t;
  }
  Control Actions(){
   var t=Columns(2);var live=Card();var video=Card();var l=Label("01   实时画面",12,ink);l.SetBounds(16,12,300,26);live.Controls.Add(l);
   var row=new FlowLayoutPanel{Location=new Point(16,49),Size=new Size(510,38),Anchor=AnchorStyles.Top|AnchorStyles.Left|AnchorStyles.Right,WrapContents=false};
   row.Controls.Add(Action("冻结  F",70,"冻结画面",true));resume=Action("恢复实时  U",85,"恢复实时");clear=Action("清空缓存  C",67,"清空缓存");row.Controls.Add(resume);row.Controls.Add(clear);live.Controls.Add(row);
   var hint=Label("上位机统一控制 · 板上实体按键全部禁用（视频 / 识别 / DDR / 背景）",8,muted);hint.SetBounds(16,94,510,22);live.Controls.Add(hint);
   var vr2=new FlowLayoutPanel{Location=new Point(16,116),Size=new Size(510,38),WrapContents=false};
   medianButton=VideoAction("中值：开",delegate{if(board.HasVideoConfig)SendVideo(board.MedianEnabled?(byte)109:(byte)77,board.MedianEnabled?"关闭中值滤波":"开启中值滤波");});vr2.Controls.Add(medianButton);
   displayButton=VideoAction("画面：彩色",delegate{if(board.HasVideoConfig)SendVideo(board.ColorMode?(byte)71:(byte)75,board.ColorMode?"切换到边缘":"切换到彩色");});vr2.Controls.Add(displayButton);
   // '+' raises the numeric threshold and suppresses weaker edges;
   // '−' lowers the numeric threshold and exposes more edge detail.
   thresholdUpButton=VideoAction("阈值 +",delegate{SendVideo(43,"提高阈值（减少边缘）");});vr2.Controls.Add(thresholdUpButton);
   thresholdDownButton=VideoAction("阈值 −",delegate{SendVideo(45,"降低阈值（增加边缘）");});vr2.Controls.Add(thresholdDownButton);
   algorithmButton=VideoAction("算法：Canny",delegate{if(board.HasVideoConfig)SendVideo(board.CannyMode?(byte)83:(byte)89,board.CannyMode?"切换到 Sobel":"切换到 Canny");});algorithmButton.Width=128;thresholdUpButton.Width=64;thresholdDownButton.Width=64;vr2.Controls.Add(algorithmButton);live.Controls.Add(vr2);
   processingStatus=Label("图像处理状态由 FPGA 回传",9,cyan);processingStatus.SetBounds(16,154,510,30);live.Controls.Add(processingStatus);
   detectionButton=VideoAction("识别：关",delegate{if(board.HasModel)SendVideo(board.DetectEnabled?(byte)100:(byte)68,board.DetectEnabled?"关闭板端识别":"开启板端识别");});detectionButton.SetBounds(16,186,105,32);live.Controls.Add(detectionButton);
   backgroundButton=VideoAction("采集空背景",delegate{calibrationBefore=board.CalibrationGeneration;SendVideo(74,"采集空布料背景");});backgroundButton.SetBounds(130,186,112,32);live.Controls.Add(backgroundButton);
   detectionStatus=Label("四种饮料 · 固定布料背景 · 单物体",8,muted);detectionStatus.SetBounds(250,186,270,32);detectionStatus.TextAlign=ContentAlignment.MiddleLeft;live.Controls.Add(detectionStatus);
   var v=Label("02   短片录制与回放",12,ink);v.SetBounds(16,12,300,26);video.Controls.Add(v);
   var vr=new FlowLayoutPanel{Location=new Point(16,49),Size=new Size(510,38),WrapContents=false};
   record=Action("录制 26 帧  V",86,"录制 26 帧",true);play=Action("循环回放  P",80,"循环回放");vr.Controls.Add(record);vr.Controls.Add(play);
   videoState=Label("等待板上状态",9,muted);videoState.Size=new Size(180,36);videoState.TextAlign=ContentAlignment.MiddleLeft;vr.Controls.Add(videoState);video.Controls.Add(vr);
   progress=Label("保存 26 个完成帧 · 采集时长取决于处理速度 · 5 fps 回放",9,muted);progress.SetBounds(16,102,510,24);video.Controls.Add(progress);t.Controls.Add(live,0,0);t.Controls.Add(video,1,0);return t;
  }
  Control Slots(){
   var t=Columns(3);for(int i=0;i<3;i++){int n=i;var p=Card();var h=Label("静态帧  /  SLOT 0"+(i+1),11,muted);h.SetBounds(16,12,290,24);p.Controls.Add(h);
    slotState[i]=Label("等待实体板",15,ink);slotState[i].SetBounds(16,41,290,30);p.Controls.Add(slotState[i]);
    var row=new FlowLayoutPanel{Location=new Point(16,87),Size=new Size(310,40),WrapContents=false};
    saveButtons[i]=Action("保存到此槽",(byte)(64+n),"保存静态帧 "+(n+1),true);showButtons[i]=Action("显示此帧",(byte)(96+n),"显示静态帧 "+(n+1));row.Controls.Add(saveButtons[i]);row.Controls.Add(showButtons[i]);p.Controls.Add(row);t.Controls.Add(p,i,0);
   }return t;
  }
  Control LogPanel(){var p=Card();p.Padding=new Padding(14,10,14,8);footer=Label("串口事件 · 仅记录真实回传",9,muted);footer.Dock=DockStyle.Top;footer.Height=26;
   log=new TextBox{Dock=DockStyle.Fill,Multiline=true,ReadOnly=true,ScrollBars=ScrollBars.Vertical,BackColor=bg,ForeColor=muted,BorderStyle=BorderStyle.None,Font=new Font("Consolas",9F)};p.Controls.Add(log);p.Controls.Add(footer);return p;}
  void OpenLog(){try{string dir=Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"logs");Directory.CreateDirectory(dir);logfile=new StreamWriter(Path.Combine(dir,"session_"+DateTime.Now.ToString("yyyyMMdd_HHmmss")+".log"),false,Encoding.UTF8);logfile.AutoFlush=true;}catch(Exception e){Log("日志文件无法创建："+e.Message);}}
  void Log(string text){string s=DateTime.Now.ToString("HH:mm:ss.fff")+"  "+text;if(log.TextLength>45000)log.Clear();log.AppendText(s+Environment.NewLine);if(logfile!=null){try{logfile.WriteLine(s);}catch{logfile.Dispose();logfile=null;}}}
  void RefreshPorts(){if(port!=null)return;string old=ports.Text;var names=SerialPort.GetPortNames();Array.Sort(names);ports.Items.Clear();ports.Items.AddRange(names);if(Array.IndexOf(names,old)>=0)ports.SelectedItem=old;else if(Array.IndexOf(names,"COM7")>=0)ports.SelectedItem="COM7";else if(names.Length>0)ports.SelectedIndex=0;}
  void Connect(){
   if(ports.SelectedItem==null){Log("未发现串口，请检查开发板 USB 连接。");return;}
   try{port=new SerialPort(ports.Text,115200,Parity.None,8,StopBits.One);port.Handshake=Handshake.None;port.DtrEnable=false;port.RtsEnable=false;port.ReadTimeout=100;port.WriteTimeout=300;port.Open();port.DiscardInBuffer();board.Reset();decoder.Reset();lastState=lastFlags=-1;opened=DateTime.UtcNow;wasFresh=false;Log("串口已打开："+port.PortName+"；等待 FPGA 身份与状态。");Query();}
   catch(Exception e){Log("连接失败："+e.Message);Disconnect();}UpdateView();
  }
  void Disconnect(){
   if(port!=null){try{port.Close();port.Dispose();}catch{}port=null;Log("串口已断开。");}
   if(pending.HasValue||pendingVideoCommand.HasValue)Log("操作结果未知：连接已关闭。");pending=null;pendingVideoCommand=null;pendingVideoName=null;accepted=false;board.Reset();decoder.Reset();wasFresh=false;
   if(operation!=null){operation.Text="未连接 · 槽位与录像状态未知";operation.ForeColor=muted;UpdateView();}
  }
  void Query(){port.Write(new byte[]{63},0,1);lastQuery=DateTime.UtcNow;}
  void Send(byte cmd,string name){
   if(port==null||!board.Fresh(DateTime.UtcNow)||pending.HasValue)return;
   try{port.Write(new byte[]{cmd},0,1);pending=cmd;pendingName=name;accepted=false;sent=DateTime.UtcNow;operation.Text=name+"：已发送，等待 FPGA 确认…";operation.ForeColor=amber;Log("TX "+cmd.ToString("X2")+"  "+name);}
   catch(Exception e){Log("发送失败："+e.Message);Disconnect();}UpdateView();
  }
  void SendVideo(byte cmd,string name){
   if(port==null||!board.Fresh(DateTime.UtcNow)||!board.HasVideoConfig||pendingVideoCommand.HasValue||pending.HasValue)return;
   pendingVideoCommand=cmd;pendingVideoName=name;pendingVideoThreshold=board.VideoThreshold;videoSent=DateTime.UtcNow;
   if(cmd==43)pendingVideoThreshold=(ushort)(pendingVideoThreshold<246?pendingVideoThreshold+4:255);
   else if(cmd==45)pendingVideoThreshold=(ushort)(pendingVideoThreshold>19?pendingVideoThreshold-4:16);
   try{port.Write(new byte[]{cmd},0,1);operation.Text=name+"：已发送，等待 FPGA 状态回传确认…";operation.ForeColor=amber;Log("TX "+cmd.ToString("X2")+"  "+name);}
   catch(Exception e){pendingVideoCommand=null;pendingVideoName=null;Log("发送失败："+e.Message);Disconnect();}UpdateView();
  }
  bool VideoCommandConfirmed(){
   if(!pendingVideoCommand.HasValue||!board.HasVideoConfig)return false;
   switch(pendingVideoCommand.Value){
    case 75:return board.ColorMode;case 71:return !board.ColorMode;
    case 43:case 45:return board.VideoThreshold==pendingVideoThreshold;
    case 83:return !board.CannyMode;case 89:return board.CannyMode;
    case 77:return board.MedianEnabled;case 109:return !board.MedianEnabled;
    case 68:return board.DetectEnabled;case 100:return !board.DetectEnabled;
    case 74:return board.HasModel&&board.BackgroundReady&&board.CalibrationGeneration!=calibrationBefore;
    default:return false;
   }
  }
  void Poll(object sender,EventArgs e){
   if(port==null)return;
   try{
    int available=port.BytesToRead;if(available>0){byte[] data=new byte[Math.Min(8192,available)];int n=port.Read(data,0,data.Length);if(n!=data.Length)Array.Resize(ref data,n);foreach(byte[] f in decoder.Feed(data))Apply(f);}
    DateTime now=DateTime.UtcNow;if((now-lastQuery).TotalSeconds>=1)Query();bool fresh=board.Fresh(now);
    if(wasFresh&&!fresh){Log("状态超时，已禁用控制；当前结果未知，正在重新查询。");board.Reset();if(pending.HasValue){pending=null;operation.Text="状态超时 · 操作结果未知";operation.ForeColor=amber;}}
    if(!wasFresh&&fresh){Log("FPGA 握手成功：EV 协议 02，状态/健康回传正常。");if(!pending.HasValue){operation.Text="FPGA 已连接 · 请查看链路健康，再执行保存/录制。";operation.ForeColor=cyan;}}wasFresh=fresh;
    if(pending.HasValue&&(now-sent).TotalSeconds>(accepted&&board.HasCanny?(pending.Value==86?180:30):5)){Log(pendingName+"超时："+(accepted?"已确认命令，未收到完成状态。":"未收到命令确认。"));operation.Text=pendingName+"超时 · 请检查板上画面，结果未知";operation.ForeColor=amber;pending=null;}
    if(pendingVideoCommand.HasValue&&(now-videoSent).TotalSeconds>3){Log(pendingVideoName+"超时：未收到匹配的 FPGA 配置回传。");operation.Text=pendingVideoName+"超时 · 当前状态未知";operation.ForeColor=amber;pendingVideoCommand=null;pendingVideoName=null;}
    UpdateView();
   }catch(Exception ex){Log("串口异常："+ex.Message);Disconnect();}
  }
  void Apply(byte[] f){
   DateTime now=DateTime.UtcNow;
   if(f[1]==4&&(!board.HasHealth||board.WriteCount!=f[3]))lastWriteChange=now;
   board.Apply(f,now);
   if((f[1]==13||f[1]==15)&&VideoCommandConfirmed()){
    operation.Text=pendingVideoName+"：FPGA 状态回传已确认。";operation.ForeColor=green;Log("配置确认："+pendingVideoName);pendingVideoCommand=null;pendingVideoName=null;
   }
   if(f[1]==10){
    string summary="链路事件 RX失锁="+board.RxLoss+" 帧不合格="+board.QualificationLoss+" TX复位="+board.TxResetLoss+" 全局复位="+board.GlobalResetLoss+" TX锁相丢失="+board.TxPllLoss+" DDR失校准="+board.CalLoss+" HS异常="+board.HsErrors+" VS异常="+board.VsErrors+" 像素时序异常="+board.PixelGeometryErrors+" RX复位="+board.RxResetLoss+" 状态=0x"+board.LinkFlags.ToString("X2");
    if(summary!=lastLinkSummary){Log(summary);lastLinkSummary=summary;}
   }
   if(f[1]==1||f[1]==3){Log("RX "+BitConverter.ToString(f));if(pending.HasValue&&f[2]==pending.Value){
    if(f[1]==3){string[] reason={"","槽位已有数据，请先清空","尚未完成录像","槽位无效或为空"};operation.Text="板上拒绝："+reason[f[3]];operation.ForeColor=amber;Log(operation.Text);pending=null;}
    else{accepted=true;operation.Text=pendingName+"：FPGA 已确认命令，等待完成状态…";operation.ForeColor=amber;}
   }}
   if(f[1]==2){if(board.State!=lastState||board.Flags!=lastFlags){Log("DDR state="+board.State+" flags=0x"+board.Flags.ToString("X2")+" progress="+board.Progress);lastState=board.State;lastFlags=board.Flags;}
    if(pending.HasValue&&accepted&&board.Completed(pending.Value)){operation.Text=pendingName+"：板上状态已确认；画面效果请看 HDMI 显示器。";operation.ForeColor=green;Log("完成状态："+pendingName);pending=null;}
   }
  }
  void UpdateView(){
   bool isOpen=port!=null;bool fresh=isOpen&&board.Fresh(DateTime.UtcNow);ports.Enabled=refresh.Enabled=!isOpen;connect.Text=isOpen?"断开设备":"连接设备";
   bool stalled=fresh&&board.State==0&&(DateTime.UtcNow-lastWriteChange).TotalSeconds>2&&(!board.HasCanny||!board.CannyBusy||(DateTime.UtcNow-board.LastCannyProgress).TotalSeconds>5);
   if(stalled&&!writeStalled){Log("告警：实时结果长时间未更新，且未观察到处理进度；画面可能停在旧帧。");if(!pending.HasValue){operation.Text="写帧停滞 · 已收到命令状态不代表实时图像仍在更新";operation.ForeColor=amber;}}
   writeStalled=stalled;
   if(stalled&&(DateTime.UtcNow-lastDiagnosticLog).TotalSeconds>=1){lastDiagnosticLog=DateTime.UtcNow;Log("诊断 health="+board.Health.ToString("X2")+" input="+board.InputFrames+" write="+board.WriteCount+" read="+board.ReadCount+" writer=0x"+board.WriterFlags.ToString("X2")+" fifo="+(board.FifoLevel*8));}
   connection.Text=fresh?"●  FPGA 已握手 · 状态实时":isOpen?((DateTime.UtcNow-opened).TotalSeconds>3?"●  串口打开 · 未收到有效握手":"●  串口打开 · 等待 FPGA…"):"●  未连接";connection.ForeColor=fresh?green:isOpen?amber:muted;
   string[] states={"实时画面","冻结画面","保存静态帧","录制中","循环回放","显示静态帧"};mode.Text=fresh?states[board.State]:"—";
   health.Text=fresh?(((board.Health&1)!=0?"DDR ✓":"DDR ×")+"   "+((board.Health&2)!=0?"RX ✓":"RX ×")+"   "+((board.Health&4)!=0?"帧 ✓":"帧 ×")):"等待回传";health.ForeColor=fresh&&(board.Health&15)==7?green:amber;
   writeCount.Text=fresh?board.WriteCount.ToString("D3"):"—";readCount.Text=fresh?board.ReadCount.ToString("D3"):"—";
   writeCount.ForeColor=writeStalled?amber:ink;
   bool ready=fresh&&!pending.HasValue&&board.State!=2&&board.State!=3;foreach(Button b in actionButtons)b.Enabled=ready;
   resume.Enabled=clear.Enabled=fresh&&!pending.HasValue;
   for(int i=0;i<3;i++){slotState[i].Text=!fresh?"状态未知":board.Slot(i)?"已保存 · 可显示":writeStalled?"空槽 · 写入停滞":(board.Health&7)==7?"空槽 · 可保存":"空槽 · 等待视频输入";slotState[i].ForeColor=fresh&&board.Slot(i)?cyan:muted;saveButtons[i].Enabled=ready&&!board.Slot(i)&&(board.Health&7)==7&&!writeStalled;showButtons[i].Enabled=ready&&board.Slot(i);}
   record.Enabled=ready&&(board.Health&7)==7&&!writeStalled;play.Enabled=ready&&board.Video;
   videoState.Text=!fresh?"等待板上状态":board.State==3?"正在录制…":board.Video?"26 帧已就绪":"未录制";videoState.ForeColor=fresh&&board.Video?green:muted;
   medianButton.Text=board.HasVideoConfig?(board.MedianEnabled?"中值：开":"中值：关"):"中值：—";
   displayButton.Text=board.HasVideoConfig?(board.ColorMode?"画面：彩色":"画面：边缘"):"画面：—";
   algorithmButton.Text=board.HasVideoConfig?(board.CannyMode?"算法：Canny":"算法：Sobel"):"算法：—";
   string videoInfo=fresh&&board.HasVideoConfig?((board.ColorMode?"彩色":"边缘")+" · "+(board.CannyMode?"Canny":"Sobel")+" · 中值 "+(board.MedianEnabled?"开":"关")+" · 阈值 "+board.VideoThreshold):"等待视频配置回传";
   if(board.HasCanny)videoInfo+=" · "+board.CompletedFps.ToString("0.0")+" 结果帧/秒 · "+(board.CannyBusy?"处理中":"完成");
   if(fresh)videoInfo+=" · 输入 "+board.InputFps.ToString("0.0")+" / 结果 "+board.CompletedFps.ToString("0.0")+" / 输出 "+board.OutputFps.ToString("0.0")+" fps";
   processingStatus.Text=videoInfo;
   foreach(Button b in videoButtons)b.Enabled=fresh&&board.HasVideoConfig&&!pending.HasValue&&!pendingVideoCommand.HasValue;
   bool modelReady=fresh&&board.HasModel&&board.HasFirmware&&(board.FirmwareId==0x110306);
   detectionButton.Enabled=detectionButton.Enabled&&modelReady;
   backgroundButton.Enabled=backgroundButton.Enabled&&modelReady&&(board.Health&7)==7;
   algorithmButton.Enabled=algorithmButton.Enabled&&modelReady;
   detectionButton.Text=board.HasModel?(board.DetectEnabled?"识别：开":"识别：关"):"识别：未部署";
   string[] drinks={"乌苏啤酒 ¥8","小可口可乐 ¥2.5","小青柠 ¥5","百事可乐 ¥3","背景（无饮料）","未识别"};
   detectionStatus.Text=!modelReady?"当前固件不提供板端 CNN":board.Calibrating?"正在采集空背景…":!board.BackgroundReady?"先移走饮料，再点“采集空背景”":!board.DetectEnabled?"背景已就绪 · 可开启识别":(board.DetectionValid?drinks[Math.Min(5,(int)board.ModelClass)]:(board.ModelClass==4?"空背景 · 不显示框":"等待饮料进入画面"))+" · CNN "+board.ModelFps.ToString("0.0")+" fps";

   progress.Text=fresh&&board.State==3?"板上录制进度："+board.Progress+" / 26 帧":"保存 26 个完成帧 · 采集时长取决于处理速度 · 5 fps 回放";
   footer.Text=(board.HasFirmware?"FW "+board.FirmwareId.ToString("X6"):"FW 未提供唯一版本号")+" · 串口事件 · 实体板回传"+(fresh?" · 更新 "+(DateTime.UtcNow-board.LastStatus).TotalMilliseconds.ToString("0")+" ms":"")+" · 丢弃异常帧 "+decoder.BadFrames+(fresh&&(board.Health&8)!=0?" · 命令队列曾溢出":"");
   if(fresh&&board.HasCanny)footer.Text+=" · 处理丢帧/错误 "+board.CannyErrors;
   if(fresh&&board.HasDiagnostics)footer.Text+=" · 输入帧 "+board.InputFrames+" · 写状态 0x"+board.WriterFlags.ToString("X2")+" · FIFO "+(board.FifoLevel*8);
  }
  [STAThread]public static void Main(string[] args){
   Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);
   var form=new MainForm();
   string render=null,autoPort=null;bool maximize=false;int screenIndex=-1;
   for(int i=0;i<args.Length;i++){int parsed;if(i+1<args.Length&&args[i]=="--render")render=args[++i];else if(i+1<args.Length&&args[i]=="--connect")autoPort=args[++i];else if(i+1<args.Length&&args[i]=="--screen"&&int.TryParse(args[++i],out parsed))screenIndex=parsed;else if(args[i]=="--maximize")maximize=true;}
   if(render!=null){
   Size renderSize=new Size(1180,850);
   for(int i=0;i+1<args.Length;i++)if(args[i]=="--size"){string[] parts=args[++i].Split('x','X');int w,h;if(parts.Length==2&&int.TryParse(parts[0],out w)&&int.TryParse(parts[1],out h))renderSize=new Size(w,h);}
   form.Show();Application.DoEvents();
   if(render!=null&&renderSize.Width>1180){form.ClientSize=renderSize;Application.DoEvents();}
    if(autoPort!=null){form.ports.SelectedItem=autoPort;form.Connect();var until=DateTime.UtcNow.AddSeconds(3);while(DateTime.UtcNow<until){Application.DoEvents();System.Threading.Thread.Sleep(10);}}
    using(var bitmap=new Bitmap(form.Width,form.Height)){form.DrawToBitmap(bitmap,new Rectangle(0,0,form.Width,form.Height));bitmap.Save(render,System.Drawing.Imaging.ImageFormat.Png);}
    form.Close();return;
   }
   if(maximize||screenIndex>=0)form.Shown+=delegate{
    Screen[] screens=Screen.AllScreens;
    if(screenIndex>=0&&screenIndex<screens.Length){form.StartPosition=FormStartPosition.Manual;form.WindowState=FormWindowState.Normal;form.Bounds=screens[screenIndex].WorkingArea;}
    if(maximize)form.WindowState=FormWindowState.Maximized;
   };
   if(autoPort!=null)form.Shown+=delegate{form.ports.SelectedItem=autoPort;form.Connect();};
   Application.Run(form);
  }
 }
}
