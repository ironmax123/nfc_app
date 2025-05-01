import 'dart:async';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/platform_tags.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.blue,
        ),
      ),
      home: const FelicaBalanceReader(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class FelicaBalanceReader extends HookWidget {
  const FelicaBalanceReader({super.key});

  @override
  Widget build(BuildContext context) {
    final result = useState('タッチして残高を取得');
    final cardId = useState('');
    final errorMessage = useState('');
    final isAvailable = useState(false);
    final isReading = useState(false);
    List<int> _createReadWithoutEncryptionCommand(
      List<int> idm,
      List<int> serviceCode,
      List<int> blockList,
    ) {
      return [
        0, // ダミー。あとで長さを入れる
        0x06, // コマンドコード: Read Without Encryption
        ...idm, // IDm
        1, // サービス数
        serviceCode[0] & 0xff, serviceCode[0] >> 8, // サービスコード（リトルエンディアン）
        1, // ブロック数
        ...blockList, // ブロック指定
      ]..[0] = 1 + 1 + idm.length + 1 + 2 + 1 + blockList.length; // 最初にパケット長を設定
    }

    Future<void> readBalance() async {
      isReading.value = true;
      result.value = '読み取り中...';

      final completer = Completer<void>();

      await NfcManager.instance.startSession(
        onDiscovered: (NfcTag tag) async {
          try {
            final nfcF = NfcF.from(tag);
            if (nfcF == null) throw Exception("NfcF not available");

            final idm = nfcF.identifier;

            // 残高読み出しコマンド（履歴取得サービス）
            final serviceCode = [0x090f, 0x090f]; // 利用履歴読み取りサービスコード

            final blockList = [0x80, 0x00]; // ブロック指定（最新）

            final command = _createReadWithoutEncryptionCommand(
                idm, serviceCode, blockList);
            final response =
                await nfcF.transceive(data: Uint8List.fromList(command));

            log(response.length.toString());

            if (response.length < 29) {
              await NfcManager.instance
                  .stopSession(errorMessage: '対応していないカードです');
              result.value = 'このカードには対応していません';
              return;
            }

            // 残高は10, 11バイト目（2バイト）
            final blockData = response.sublist(13, 29); // 最初のブロック（16バイト）
            final balance = blockData[10] + (blockData[11] << 8);
            result.value = '残高: ¥$balance';

            await NfcManager.instance.stopSession();
          } catch (e) {
            await NfcManager.instance.stopSession(errorMessage: 'エラーが発生しました');
            result.value = 'エラー: $e';
            log('Error: $e');
          } finally {
            isReading.value = false;
            completer.complete();
          }
        },
      );

      await completer.future;
    }

    Future<void> _checkNfcAvailability() async {
      log('Checking NFC availability...');
      try {
        final availability = await NfcManager.instance.isAvailable();
        log('NFC Availability: $availability');

        isAvailable.value = availability;
        if (!availability) {
          errorMessage.value = 'NFCが無効になっています。\n設定でNFCを有効にしてください。';
        } else {
          errorMessage.value = '';
        }
      } catch (e) {
        log('NFC Check Error: $e');

        isAvailable.value = false;
        errorMessage.value = 'NFCの確認中にエラーが発生しました: $e';
      }
    }

    useEffect(() {
      _checkNfcAvailability();
      return null;
    }, []);
    return Scaffold(
      appBar: AppBar(title: const Text('交通系IC残高リーダー')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (!isAvailable.value)
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'NFCは利用できません。\nデバイスがNFCに対応しているか確認してください。',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.red),
                ),
              )
            else ...[
              Icon(
                isReading.value ? Icons.nfc : Icons.nfc_outlined,
                size: 100,
                color: isReading.value ? Colors.blue : Colors.grey,
              ),
              const SizedBox(height: 20),
              if (isReading.value)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text(
                        'NFCカードを近づけてください',
                        style: TextStyle(fontSize: 18),
                      ),
                    ],
                  ),
                ),
              if (cardId.value.isNotEmpty) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'カードID',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        cardId.value,
                        style: const TextStyle(fontSize: 18),
                      ),
                    ],
                  ),
                ),
              ],
              Text(
                result.value,
                style: const TextStyle(fontSize: 28),
              ),
              ElevatedButton.icon(
                onPressed: isReading.value ? null : readBalance,
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      isReading.value ? Colors.grey : Colors.blue[100],
                  padding: const EdgeInsets.symmetric(
                    horizontal: 40,
                    vertical: 16,
                  ),
                ),
                icon: const Icon(
                  Icons.nfc,
                  color: Colors.black,
                ),
                label: Text(
                  isReading.value ? '読み取り中...' : 'NFCを読み取る',
                  style: const TextStyle(
                    fontSize: 18,
                    color: Colors.black,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
