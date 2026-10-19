import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';

void main() => runApp(const WifiExplorerApp());

const navy = Color(0xFF10243A);
const teal = Color(0xFF12B8A6);

class WifiExplorerApp extends StatelessWidget {
  const WifiExplorerApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'كاشف الشبكات الذكي',
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: teal, brightness: Brightness.light), scaffoldBackgroundColor: const Color(0xFFF3F7FA), useMaterial3: true),
    home: const Directionality(textDirection: TextDirection.rtl, child: ExplorerHome()),
  );
}

class WifiNetwork {
  final String ssid, bssid, security;
  final int level, frequency, channel;
  const WifiNetwork({required this.ssid, required this.bssid, required this.security, required this.level, required this.frequency, required this.channel});
  factory WifiNetwork.fromMap(Map<dynamic,dynamic> m) => WifiNetwork(
    ssid: (m['ssid'] ?? '').toString().isEmpty ? 'شبكة مخفية' : m['ssid'].toString(),
    bssid: (m['bssid'] ?? '').toString(), security: (m['security'] ?? 'غير معروف').toString(),
    level: (m['level'] as num?)?.toInt() ?? -100, frequency: (m['frequency'] as num?)?.toInt() ?? 0,
    channel: (m['channel'] as num?)?.toInt() ?? 0);
  String get band => frequency >= 5925 ? '6 غيغاهرتز' : frequency >= 4900 ? '5 غيغاهرتز' : frequency > 0 ? '2.4 غيغاهرتز' : 'غير معروف';
  String get signal => level >= -50 ? 'ممتازة' : level >= -60 ? 'قوية' : level >= -70 ? 'متوسطة' : 'ضعيفة';
}

class ExplorerHome extends StatefulWidget {
  const ExplorerHome({super.key});
  @override
  State<ExplorerHome> createState() => _ExplorerHomeState();
}
class _ExplorerHomeState extends State<ExplorerHome> {
  static const platform = MethodChannel('wifi_explorer/scan');
  int tab = 0;
  bool scanning = false, searching = false;
  String message = 'اضغط «فحص الشبكات» لبدء المسح على هذا الجهاز.';
  List<WifiNetwork> networks = [];
  List<Map<String,dynamic>> hotspots = [];
  final query = TextEditingController();
  final locationQuery = TextEditingController(text: 'إب، اليمن');
  final Set<String> favorites = {};
  final List<String> history = [];
  List<WifiNetwork> get visibleNetworks => networks.where((n) => ('${n.ssid} ${n.security} ${n.band}').toLowerCase().contains(query.text.toLowerCase())).toList();

  Future<void> scan() async {
    setState(() { scanning = true; message = 'جارٍ طلب الأذونات وفحص الشبكات…'; });
    try {
      final loc = await Permission.locationWhenInUse.request();
      if (!loc.isGranted) { setState(() => message = 'يلزم السماح بإذن الموقع لأن Android يربط مسح Wi‑Fi به في كثير من الإصدارات.'); return; }
      final nearby = await Permission.nearbyWifiDevices.request();
      if (!nearby.isGranted && await Permission.nearbyWifiDevices.isPermanentlyDenied) {
        setState(() => message = 'إذن أجهزة Wi‑Fi القريبة مرفوض نهائيًا. افتح إعدادات التطبيق واسمح بالإذن.'); return;
      }
      final result = await platform.invokeMethod<List<dynamic>>('scanNetworks');
      networks = (result ?? []).map((e) => WifiNetwork.fromMap(Map<dynamic,dynamic>.from(e as Map))).toList()
        ..sort((a,b) => b.level.compareTo(a.level));
      history.insert(0, 'فحص ${DateTime.now().toLocal().toString().substring(0,16)} — ${networks.length} شبكة');
      message = networks.isEmpty ? 'لم تُرجع المنظومة شبكات. تأكد من تشغيل Wi‑Fi والموقع، ثم أعد المحاولة.' : 'تم العثور على ${networks.length} شبكة قريبة.';
    } on PlatformException catch (e) { message = 'تعذر الفحص: ${e.message ?? e.code}'; }
      catch (e) { message = 'تعذر إكمال الفحص. تحقق من الأذونات وتشغيل Wi‑Fi.'; }
    finally { if (mounted) setState(() => scanning = false); }
  }

  Future<void> searchPublicHotspots() async {
    setState(() { searching = true; message = 'جارٍ تحديد الموقع والبحث في بيانات OpenStreetMap…'; });
    try {
      final place = locationQuery.text.trim();
      if (place.isEmpty) throw Exception('اكتب اسم مدينة أو منطقة أولًا');
      final geocodeUri = Uri.https('nominatim.openstreetmap.org', '/search', {'q': place, 'format': 'jsonv2', 'limit': '1'});
      final geoResponse = await http.get(geocodeUri, headers: {'User-Agent': 'WiFiExplorer/1.0 (public hotspot map search)'}).timeout(const Duration(seconds: 20));
      if (geoResponse.statusCode != 200) throw Exception('تعذر تحديد الموقع');
      final geo = jsonDecode(geoResponse.body) as List;
      if (geo.isEmpty) throw Exception('لم يتم العثور على الموقع. جرّب اسمًا أوضح.');
      final latitude = double.parse(geo.first['lat'].toString());
      final longitude = double.parse(geo.first['lon'].toString());
      final overpass = Uri.parse('https://overpass-api.de/api/interpreter');
      final body = '[out:json][timeout:25];(node["internet_access"="wlan"](around:10000,$latitude,$longitude);way["internet_access"="wlan"](around:10000,$latitude,$longitude);node["amenity"="internet_cafe"](around:10000,$latitude,$longitude););out center tags;';
      final response = await http.post(overpass, headers: {'Content-Type':'application/x-www-form-urlencoded; charset=UTF-8'}, body: {'data': body}).timeout(const Duration(seconds: 35));
      if (response.statusCode != 200) throw Exception('خدمة بيانات الخرائط غير متاحة الآن');
      final data = jsonDecode(response.body) as Map<String,dynamic>;
      hotspots = ((data['elements'] as List?) ?? []).map((e) {
        final el = Map<String,dynamic>.from(e as Map);
        final tags = Map<String,dynamic>.from((el['tags'] as Map?) ?? {});
        return <String,dynamic>{
          'name': tags['name'] ?? tags['brand'] ?? tags['operator'] ?? 'نقطة اتصال عامة غير مسماة',
          'type': tags['amenity'] == 'internet_cafe' ? 'مقهى إنترنت' : 'واي فاي عام',
          'lat': el['lat'] ?? (el['center'] as Map?)?['lat'],
          'lon': el['lon'] ?? (el['center'] as Map?)?['lon'],
          'access': tags['internet_access'] ?? 'غير محدد',
          'address': [tags['addr:street'], tags['addr:city']].where((x) => x != null).join('، ')
        };
      }).toList();
      message = 'نتائج ضمن 10 كم من $place. بيانات الخرائط قد تكون ناقصة ولا تؤكد أن الشبكة تعمل حاليًا.';
    } catch (e) {
      message = e.toString().contains('Exception:') ? e.toString().replaceFirst('Exception: ', '') : 'تعذر البحث عبر الإنترنت. تحقق من الاتصال ثم أعد المحاولة.';
    } finally { if (mounted) setState(() => searching = false); }
  }

  @override
  void dispose() { query.dispose(); locationQuery.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final titles = ['الشبكات القريبة', 'نقاط الاتصال العامة', 'المفضلة', 'سجل الفحص'];
    return Scaffold(
      appBar: AppBar(backgroundColor: navy, foregroundColor: Colors.white, title: const Row(children: [Icon(Icons.wifi_tethering, color: teal), SizedBox(width:10), Text('كاشف الشبكات الذكي', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))]),),
      body: Column(children: [
        Container(width: double.infinity, padding: const EdgeInsets.fromLTRB(18,18,18,20), decoration: const BoxDecoration(color: navy, borderRadius: BorderRadius.vertical(bottom: Radius.circular(24))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('افهم شبكتك بوضوح', style: TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.bold)),
          const SizedBox(height:6), const Text('تحليل الإشارة • التردد • القناة • الحماية', style: TextStyle(color: Color(0xFFD3E1EC))),
          const SizedBox(height:16), Row(children: [
            Expanded(child: FilledButton.icon(onPressed: scanning ? null : scan, icon: scanning ? const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2,color:Colors.white)) : const Icon(Icons.radar), label: Text(scanning ? 'جارٍ الفحص…' : 'فحص الشبكات'), style: FilledButton.styleFrom(backgroundColor: teal, foregroundColor: navy, padding: const EdgeInsets.symmetric(vertical:14)))),
            const SizedBox(width:10), Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white.withValues(alpha:.10), borderRadius: BorderRadius.circular(12)), child: Text('${networks.length} شبكة', style: const TextStyle(color:Colors.white,fontWeight:FontWeight.bold)))
          ])
        ])),
        Padding(padding: const EdgeInsets.fromLTRB(16,12,16,4), child: Container(width:double.infinity,padding:const EdgeInsets.all(12),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(12)),child: Text(message, style: const TextStyle(fontSize:13)))),
        Padding(padding: const EdgeInsets.symmetric(horizontal:16, vertical:8), child: TextField(controller:query,onChanged:(_)=>setState((){}),decoration:InputDecoration(hintText:'ابحث عن اسم الشبكة أو التردد…',prefixIcon:const Icon(Icons.search),filled:true,fillColor:Colors.white,border:OutlineInputBorder(borderRadius:BorderRadius.circular(14),borderSide:BorderSide.none)))),
        Expanded(child: IndexedStack(index:tab, children: [
          visibleNetworks.isEmpty ? _empty('لا توجد شبكات معروضة','شغّل Wi‑Fi ثم ابدأ الفحص.') : ListView.builder(padding:const EdgeInsets.fromLTRB(16,4,16,16),itemCount:visibleNetworks.length,itemBuilder:(c,i)=>_networkCard(visibleNetworks[i])),
          Column(children:[
            Padding(padding:const EdgeInsets.fromLTRB(16,4,16,8),child:TextField(controller:locationQuery,decoration:InputDecoration(labelText:'ابحث في أي مدينة أو منطقة',hintText:'مثال: إب، اليمن أو القاهرة',prefixIcon:const Icon(Icons.location_on),filled:true,fillColor:Colors.white,border:OutlineInputBorder(borderRadius:BorderRadius.circular(14),borderSide:BorderSide.none)))),
            Padding(padding:const EdgeInsets.symmetric(horizontal:16,vertical:4),child:SizedBox(width:double.infinity,child:FilledButton.icon(onPressed:searching?null:searchPublicHotspots,icon:const Icon(Icons.public),label:Text(searching?'جارٍ البحث…':'البحث عن نقاط اتصال عامة'),style:FilledButton.styleFrom(backgroundColor:navy,foregroundColor:Colors.white)))),
            Expanded(child:hotspots.isEmpty?_empty('ابحث عن نقاط اتصال عامة','ابحث عن منطقة في أي مكان بالعالم. النتائج تعتمد على ما هو مسجل في OpenStreetMap.'):ListView.builder(padding:const EdgeInsets.all(16),itemCount:hotspots.length,itemBuilder:(c,i){final h=hotspots[i];return Card(color:Colors.white,child:ListTile(leading:const CircleAvatar(backgroundColor:Color(0xFFE1F7F3),child:Icon(Icons.public,color:navy)),title:Text(h['name'].toString()),subtitle:Text('${h['type']} • ${h['address']}\n${h['lat'] ?? ''}, ${h['lon'] ?? ''}'),isThreeLine:true,trailing:const Icon(Icons.map_outlined),onTap:()async{final lat=h['lat'];final lon=h['lon'];if(lat!=null&&lon!=null){final uri=Uri.parse('https://www.openstreetmap.org/?mlat=$lat&mlon=$lon#map=17/$lat/$lon');await launchUrl(uri,mode:LaunchMode.externalApplication);}})));}))
          ]),
          favorites.isEmpty?_empty('لا توجد مفضلات','أضف شبكة إلى المفضلة من بطاقة الشبكة.'):ListView(padding:const EdgeInsets.all(16),children:networks.where((n)=>favorites.contains(n.bssid)).map(_networkCard).toList()),
          history.isEmpty?_empty('لا يوجد سجل بعد','سيظهر سجل مختصر بعد أول فحص.'):ListView(padding:const EdgeInsets.all(16),children:history.map((h)=>Card(color:Colors.white,child:ListTile(leading:const Icon(Icons.history),title:Text(h)))).toList()),
        ])),
      ]),
      bottomNavigationBar: NavigationBar(selectedIndex:tab,onDestinationSelected:(v)=>setState(()=>tab=v),destinations:const [
        NavigationDestination(icon:Icon(Icons.wifi),label:'القريبة'),
        NavigationDestination(icon:Icon(Icons.public),label:'العامة'),
        NavigationDestination(icon:Icon(Icons.star_border),label:'المفضلة'),
        NavigationDestination(icon:Icon(Icons.history),label:'السجل'),
      ]),
    );
  }

  Widget _empty(String title,String subtitle)=>Center(child:Padding(padding:const EdgeInsets.all(30),child:Column(mainAxisSize:MainAxisSize.min,children:[const Icon(Icons.wifi_find,size:54,color:teal),const SizedBox(height:12),Text(title,style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)),const SizedBox(height:6),Text(subtitle,textAlign:TextAlign.center,style:const TextStyle(color:Colors.black54))])));
  Widget _networkCard(WifiNetwork n)=>Card(color:Colors.white,elevation:0,margin:const EdgeInsets.only(bottom:10),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(16),side:const BorderSide(color:Color(0xFFE3EAF0))),child:Padding(padding:const EdgeInsets.all(14),child:Column(children:[
    Row(children:[Container(width:46,height:46,decoration:BoxDecoration(color:const Color(0xFFE2F7F3),borderRadius:BorderRadius.circular(14)),child:Icon(n.level>=-65?Icons.wifi:Icons.wifi_2_bar,color:navy,size:28)),const SizedBox(width:12),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(n.ssid,style:const TextStyle(fontWeight:FontWeight.bold,fontSize:16),maxLines:1,overflow:TextOverflow.ellipsis),Text(n.bssid,style:const TextStyle(color:Colors.black54,fontSize:11))])),IconButton(onPressed:()=>setState(()=>favorites.contains(n.bssid)?favorites.remove(n.bssid):favorites.add(n.bssid)),icon:Icon(favorites.contains(n.bssid)?Icons.star:Icons.star_border,color:favorites.contains(n.bssid)?Colors.amber:navy))]),
    const SizedBox(height:12),Row(children:[_metric('قوة الإشارة','${n.level} dBm'),_metric('التقييم',n.signal),_metric('القناة',n.channel==0?'—':'${n.channel}')]),const Divider(height:22),Row(children:[const Icon(Icons.security,size:17,color:teal),const SizedBox(width:6),Expanded(child:Text(n.security,style:const TextStyle(fontSize:12))),Text(n.band,style:const TextStyle(fontWeight:FontWeight.w600,fontSize:12))])
  ])));
  Widget _metric(String label,String value)=>Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(label,style:const TextStyle(color:Colors.black54,fontSize:11)),const SizedBox(height:3),Text(value,style:const TextStyle(fontWeight:FontWeight.bold,fontSize:13))]));
}
