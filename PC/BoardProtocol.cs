using System;
using System.Collections.Generic;
namespace EdgeVisionControl {
 public sealed class FrameDecoder {
  readonly List<byte> buffer=new List<byte>();
  public int BadFrames {get;private set;}
  public void Reset(){buffer.Clear();BadFrames=0;}
  public List<byte[]> Feed(byte[] data){
   buffer.AddRange(data);var frames=new List<byte[]>();
   while(buffer.Count>0){
    if(buffer[0]!=165){buffer.RemoveAt(0);continue;}
    if(buffer.Count<6)break;
    byte x=0;for(int i=0;i<5;i++)x^=buffer[i];
    if(x!=buffer[5]||!Valid(buffer)){buffer.RemoveAt(0);BadFrames++;continue;}
    frames.Add(buffer.GetRange(0,6).ToArray());buffer.RemoveRange(0,6);
   }return frames;
  }
  static bool Valid(List<byte> b){
   switch(b[1]){
    case 1:return b[3]<=6&&b[4]<=2&&b[2]==Command(b[3],b[4]);
    case 2:return b[2]<=5&&b[3]<32&&b[4]<=26;
    case 3:return b[3]>=1&&b[3]<=3&&b[4]<=3;
    case 4:return b[2]<16;
    case 5:return b[2]==69&&b[3]==86&&b[4]==2;
    case 6:case 7:case 8:case 9:return true;
    case 10:return b[2]<128;
    case 11:return b[2]<16;
    case 12:return b[2]==0&&b[3]==0;
    case 13:return b[2]==0;
    case 14:return true;
    case 15:return b[2]<16&&(b[4]&7)<=5;
    case 22:case 23:case 24:case 25:case 32:case 33:return true;
    default:return false;
   }
  }
  static byte Command(int op,int arg){byte[] c={70,85,64,86,80,96,67};return(byte)(c[op]+((op==2||op==5)?arg:0));}
 }
 public sealed class RateMeter {
  DateTime last=DateTime.MinValue,start=DateTime.MinValue;int previous,total;public double Value;
  public void Reset(){last=start=DateTime.MinValue;previous=total=0;Value=0;}
  public void Add(byte n,DateTime now){
   if(last==DateTime.MinValue||(now-last).TotalSeconds>=2){start=now;total=0;Value=0;}
   else total+=(n-previous+256)%256;
   if((now-start).TotalSeconds>=2){Value=total/(now-start).TotalSeconds;start=now;total=0;}
   last=now;previous=n;
  }
 }
 public sealed class BoardState {
  public bool Identified,HasStatus,HasHealth;
  public bool HasFirmware,HasModel,BackgroundReady,Calibrating,DetectionValid,InferenceBusy;
  public int FirmwareId,CalibrationGeneration;public byte ModelClass,ModelFrames;
  readonly RateMeter inputRate=new RateMeter(),outputRate=new RateMeter(),modelRate=new RateMeter();
  public double InputFps{get{return inputRate.Value;}}public double OutputFps{get{return outputRate.Value;}}public double ModelFps{get{return modelRate.Value;}}
  public byte State,Flags,Progress,Health,WriteCount,ReadCount;
  public byte InputFrames,WriterFlags,FifoLevel;public bool HasDiagnostics;
  public byte RxLoss,QualificationLoss,TxResetLoss,GlobalResetLoss,TxPllLoss,CalLoss,HsErrors,VsErrors,TxFrames,LinkFlags,RxResetLoss;
  public bool HasLink;
  public byte PixelGeometryErrors;
  public bool HasCanny;public byte CannyFlags,CannyErrors;public ushort CannyPasses;
  public bool HasVideoConfig,DetectEnabled,ColorMode,CannyMode,MedianEnabled;public ushort VideoThreshold;public int VideoConfig;
  public bool CannyBusy {get{return(CannyFlags&1)!=0;}}
  public DateTime LastCannyProgress=DateTime.MinValue;
  public double CompletedFps;DateTime rateStart=DateTime.MinValue;int rateFrames;
  public DateTime LastStatus,LastHealth,LastIdentity;
  public bool Video {get{return(Flags&16)!=0;}}
  public bool Slot(int i){return(Flags&(1<<i))!=0;}
  public bool Fresh(DateTime now){return Identified&&HasStatus&&HasHealth&&(now-LastStatus).TotalSeconds<2&&(now-LastHealth).TotalSeconds<2;}
  public void Reset(){HasFirmware=HasModel=BackgroundReady=Calibrating=DetectionValid=InferenceBusy=false;FirmwareId=CalibrationGeneration=0;ModelClass=5;ModelFrames=0;inputRate.Reset();outputRate.Reset();modelRate.Reset();Identified=HasStatus=HasHealth=HasDiagnostics=HasLink=HasCanny=HasVideoConfig=false;State=Flags=Progress=Health=WriteCount=ReadCount=0;InputFrames=WriterFlags=FifoLevel=0;RxLoss=QualificationLoss=TxResetLoss=GlobalResetLoss=TxPllLoss=CalLoss=HsErrors=VsErrors=TxFrames=LinkFlags=RxResetLoss=PixelGeometryErrors=CannyFlags=CannyErrors=0;CannyPasses=0;VideoConfig=VideoThreshold=0;DetectEnabled=ColorMode=CannyMode=MedianEnabled=false;CompletedFps=0;rateFrames=0;rateStart=LastCannyProgress=LastStatus=LastHealth=LastIdentity=DateTime.MinValue;}
  public void Apply(byte[] b,DateTime now){
   if(b[1]==2){State=b[2];Flags=b[3];Progress=b[4];HasStatus=true;LastStatus=now;}
   if(b[1]==4){
    if(HasHealth&&(now-LastHealth).TotalSeconds<2){rateFrames+=(b[3]-WriteCount+256)%256;if(b[3]!=WriteCount)LastCannyProgress=now;}
    else{rateStart=now;rateFrames=0;CompletedFps=0;}
    if((now-rateStart).TotalSeconds>=2){CompletedFps=rateFrames/(now-rateStart).TotalSeconds;rateFrames=0;rateStart=now;}
    Health=b[2];WriteCount=b[3];ReadCount=b[4];HasHealth=true;LastHealth=now;
   }
   if(b[1]==5){Identified=true;LastIdentity=now;}
   if(b[1]==6){inputRate.Add(b[2],now);HasDiagnostics=true;InputFrames=b[2];WriterFlags=b[3];FifoLevel=b[4];}
   if(b[1]==7){RxLoss=b[2];QualificationLoss=b[3];TxResetLoss=b[4];}
   if(b[1]==8){GlobalResetLoss=b[2];TxPllLoss=b[3];CalLoss=b[4];}
   if(b[1]==9){outputRate.Add(b[4],now);HsErrors=b[2];VsErrors=b[3];TxFrames=b[4];}
   if(b[1]==10){HasLink=true;LinkFlags=b[2];RxResetLoss=b[3];PixelGeometryErrors=b[4];}
   if(b[1]==11){ushort passes=(ushort)((b[3]<<8)|b[4]);if(!HasCanny||CannyFlags!=b[2]||CannyPasses!=passes)LastCannyProgress=now;HasCanny=true;CannyFlags=b[2];CannyPasses=passes;}
   if(b[1]==12)CannyErrors=b[4];
   if(b[1]==14){HasFirmware=true;FirmwareId=(b[2]<<16)|(b[3]<<8)|b[4];}
   if(b[1]==15){HasModel=true;BackgroundReady=(b[2]&1)!=0;Calibrating=(b[2]&2)!=0;DetectionValid=(b[2]&4)!=0;InferenceBusy=(b[2]&8)!=0;ModelFrames=b[3];modelRate.Add(b[3],now);ModelClass=(byte)(b[4]&7);CalibrationGeneration=b[4]>>3;}
   if(b[1]==13){VideoConfig=(b[2]<<16)|(b[3]<<8)|b[4];DetectEnabled=(VideoConfig&0x8000)!=0;ColorMode=(VideoConfig&0x4000)!=0;CannyMode=(VideoConfig&0x2000)!=0;MedianEnabled=(VideoConfig&0x1000)!=0;VideoThreshold=(ushort)(VideoConfig&0x0fff);HasVideoConfig=true;}
  }
  public bool Completed(byte command){
   if(!HasStatus)return false;
   switch(command){
    case 70:return State==1;case 85:return State==0;
    case 64:case 65:case 66:return Slot(command-64)&&State!=2;
    case 86:return Video&&State!=3;case 80:return State==4;
    case 96:case 97:case 98:return State==5&&Slot(command-96);
    case 67:return Flags==0&&State==0;default:return false;
   }
  }
 }
}
