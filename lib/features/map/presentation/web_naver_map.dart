// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';

/// 웹에서 네이버 지도 JavaScript API v3를 HtmlElementView로 렌더링.
/// index.html에서 maps.js가 로드되어야 함.
class WebNaverMapView extends StatefulWidget {
  const WebNaverMapView({super.key});

  @override
  State<WebNaverMapView> createState() => _WebNaverMapViewState();
}

class _WebNaverMapViewState extends State<WebNaverMapView> {
  static const _viewType = 'naver-map-view';
  static bool _registered = false;

  @override
  void initState() {
    super.initState();
    if (!_registered) {
      _registered = true;
      ui_web.platformViewRegistry.registerViewFactory(
        _viewType,
        (int viewId) {
          final div = html.DivElement()
            ..id = 'naver_map_$viewId'
            ..style.width = '100%'
            ..style.height = '100%';
          _initWhenReady(div, 'naver_map_$viewId');
          return div;
        },
      );
    }
  }

  /// Naver Maps JS SDK가 로드될 때까지 300ms 간격으로 재시도.
  static void _initWhenReady(html.DivElement div, String divId) {
    final ctx = js.context;
    if (ctx.hasProperty('naver') &&
        (ctx['naver'] as js.JsObject).hasProperty('maps')) {
      _createMap(divId);
    } else {
      Future.delayed(
        const Duration(milliseconds: 300),
        () => _initWhenReady(div, divId),
      );
    }
  }

  static void _createMap(String divId) {
    try {
      final naverMaps = (js.context['naver'] as js.JsObject)['maps'] as js.JsObject;
      final center = js.JsObject(
        naverMaps['LatLng'] as js.JsFunction,
        [37.4607, 126.9526],
      );
      js.JsObject(
        naverMaps['Map'] as js.JsFunction,
        [divId, js.JsObject.jsify({'center': center, 'zoom': 15})],
      );
    } catch (_) {
      // 초기화 실패 무시 (API 키 미등록 등)
    }
  }

  @override
  Widget build(BuildContext context) {
    return const HtmlElementView(viewType: _viewType);
  }
}
