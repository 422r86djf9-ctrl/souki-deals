// Carte OpenStreetMap (Leaflet) dans une WebView : gratuite, sans clé.
// Repères mis à jour sans recharger ; toucher un commerce le sélectionne ; mode « choisir un point ».
import { useEffect, useMemo, useRef } from 'react';
import { StyleProp, View, ViewStyle } from 'react-native';
import { WebView } from 'react-native-webview';

export type MapMarker = { id: string; lat: number; lng: number; label: string; kind: 'shop' | 'me' | 'pick' };

type Props = {
  markers: MapMarker[];
  pickMode?: boolean;
  onPick?: (lat: number, lng: number) => void;
  onSelect?: (id: string) => void;
  style?: StyleProp<ViewStyle>;
};

const PARIS: [number, number] = [48.8566, 2.3522];

const HTML = `<!doctype html><html><head>
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"/>
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
<style>
 html,body,#map{height:100%;margin:0;background:#FBF8F3}
 .pin{border-radius:50%;border:3px solid #fff;box-shadow:0 2px 6px rgba(0,0,0,.35);width:22px;height:22px}
 .shop{background:#4A1650}.me{background:#1E7B4A}.pick{background:#F4A300}
 .leaflet-control-attribution{font-size:9px}
</style></head><body><div id="map"></div><script>
 var map=L.map('map',{zoomControl:true}).setView([${PARIS[0]},${PARIS[1]}],12);
 L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',{maxZoom:19,attribution:'© OpenStreetMap'}).addTo(map);
 var layers={}, fitted=false, pickMode=false;
 function icon(k){return L.divIcon({className:'',html:'<div class="pin '+k+'"></div>',iconSize:[22,22],iconAnchor:[11,11]});}
 function esc(s){return String(s).replace(/[&<>"']/g,function(c){return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c];});}
 function send(o){window.ReactNativeWebView&&window.ReactNativeWebView.postMessage(JSON.stringify(o));}
 window.dealsUpdate=function(d){
   pickMode=!!d.pickMode;
   var seen={};
   (d.markers||[]).forEach(function(m){
     seen[m.id]=1;
     if(layers[m.id]){layers[m.id].setLatLng([m.lat,m.lng]);}
     else{
       var mk=L.marker([m.lat,m.lng],{icon:icon(m.kind)}).addTo(map).bindTooltip(esc(m.label));
       if(m.kind==='shop'){mk.on('click',function(){send({type:'select',id:m.id});});}
       layers[m.id]=mk;
     }
   });
   Object.keys(layers).forEach(function(k){if(!seen[k]){map.removeLayer(layers[k]);delete layers[k];}});
   var pts=(d.markers||[]).map(function(m){return [m.lat,m.lng];});
   if(!fitted&&pts.length){
     if(pts.length===1){map.setView(pts[0],15);}else{map.fitBounds(pts,{padding:[40,40],maxZoom:16});}
     fitted=true;
   }
 };
 map.on('click',function(e){if(pickMode){send({type:'pick',lat:e.latlng.lat,lng:e.latlng.lng});}});
 send({type:'ready'});
</script></body></html>`;

export function LiveMap({ markers, pickMode, onPick, onSelect, style }: Props) {
  const ref = useRef<WebView>(null);
  const ready = useRef(false);
  const payload = useMemo(() => JSON.stringify({ markers, pickMode: !!pickMode }), [markers, pickMode]);

  function push() {
    if (ready.current) ref.current?.injectJavaScript(`window.dealsUpdate(${payload});true;`);
  }

  useEffect(push, [payload]);

  return (
    <View style={[{ height: 300, borderRadius: 16, overflow: 'hidden', backgroundColor: '#FBF8F3' }, style]}>
      <WebView
        ref={ref}
        source={{ html: HTML }}
        originWhitelist={['*']}
        javaScriptEnabled
        domStorageEnabled
        setSupportMultipleWindows={false}
        nestedScrollEnabled
        onMessage={(e) => {
          try {
            const msg = JSON.parse(e.nativeEvent.data) as { type: string; lat?: number; lng?: number; id?: string };
            if (msg.type === 'ready') {
              ready.current = true;
              push();
            } else if (msg.type === 'pick' && onPick && msg.lat != null && msg.lng != null) {
              onPick(msg.lat, msg.lng);
            } else if (msg.type === 'select' && onSelect && msg.id) {
              onSelect(msg.id);
            }
          } catch {
            // message ignoré
          }
        }}
      />
    </View>
  );
}
