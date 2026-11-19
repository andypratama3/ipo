/* ============================================================
   QRIS — parser, validator & konverter statis → dinamis
   ------------------------------------------------------------
   Di-port ke vanilla JS dari project MIT
   github.com/verssache/qris-dinamis (© Gidhan, MIT License)
   Sesuai spesifikasi EMVCo QR Code (Tag-Length-Value) dan
   standar QRIS Bank Indonesia.
   - parseTLV / parseQRIS : baca struktur payload QRIS
   - validateQRIS          : cek struktur + CRC16
   - convertQRIS           : ubah QRIS statis → dinamis
                            (tag 01 = "12" + nominal tag 54 + CRC baru)
   - calculateCRC16        : CRC16-CCITT (poly 0x1021, init 0xFFFF)
   Tanpa dependensi. Dipakai oleh POS Mie Pangsit Jakarta.
   ============================================================ */
(function (global) {
  'use strict';

  var TAG_NAMES = {
    '00': 'Payload Format Indicator',
    '01': 'Point of Initiation Method',
    '02': 'Visa',
    '03': 'Mastercard',
    '04': 'Mastercard',
    '15': 'Visa',
    '26': 'Merchant Account Information',
    '27': 'Merchant Account Information',
    '28': 'Merchant Account Information',
    '29': 'Merchant Account Information',
    '30': 'Merchant Account Information',
    '31': 'Merchant Account Information',
    '32': 'Merchant Account Information',
    '33': 'Merchant Account Information',
    '34': 'Merchant Account Information',
    '35': 'Merchant Account Information',
    '36': 'Merchant Account Information',
    '37': 'Merchant Account Information',
    '38': 'Merchant Account Information',
    '39': 'Merchant Account Information',
    '40': 'Merchant Account Information',
    '41': 'Merchant Account Information',
    '42': 'Merchant Account Information',
    '43': 'Merchant Account Information',
    '44': 'Merchant Account Information',
    '45': 'Merchant Account Information',
    '46': 'Merchant Account Information',
    '47': 'Merchant Account Information',
    '48': 'Merchant Account Information',
    '49': 'Merchant Account Information',
    '50': 'Merchant Account Information',
    '51': 'Merchant Account Information',
    '52': 'Merchant Category Code',
    '53': 'Transaction Currency',
    '54': 'Transaction Amount',
    '55': 'Tip or Convenience Indicator',
    '56': 'Value of Convenience Fee (Fixed)',
    '57': 'Value of Convenience Fee (%)',
    '58': 'Country Code',
    '59': 'Merchant Name',
    '60': 'Merchant City',
    '61': 'Postal Code',
    '62': 'Additional Data Field',
    '63': 'CRC'
  };

  // Tag yang memuat elemen TLV bersarang (jaringan merchant + data tambahan)
  var NESTED_TAGS = {};
  (function () {
    for (var i = 26; i <= 51; i += 1) NESTED_TAGS[String(i).padStart(2, '0')] = true;
    NESTED_TAGS['62'] = true;
  })();

  function parseTLV(data) {
    var elements = [];
    var pos = 0;
    while (pos < data.length) {
      if (pos + 4 > data.length) break;
      var tag = data.substring(pos, pos + 2);
      var length = parseInt(data.substring(pos + 2, pos + 4), 10);
      if (isNaN(length) || pos + 4 + length > data.length) break;
      var value = data.substring(pos + 4, pos + 4 + length);
      var element = { tag: tag, name: TAG_NAMES[tag] || ('Unknown (' + tag + ')'), length: length, value: value };
      if (NESTED_TAGS[tag]) element.children = parseTLV(value);
      elements.push(element);
      pos += 4 + length;
    }
    return elements;
  }

  function parseQRIS(qrisString) {
    var str = String(qrisString || '').trim();
    var raw = parseTLV(str);
    var findTag = function (tag) {
      for (var i = 0; i < raw.length; i += 1) if (raw[i].tag === tag) return raw[i];
      return undefined;
    };
    var methodValue = findTag('01') ? findTag('01').value : '';
    var tipIndicatorValue = findTag('55') ? findTag('55').value : '';
    var merchantAccountInfo = [];
    for (var i = 0; i < raw.length; i += 1) {
      var t = raw[i];
      var tagNum = parseInt(t.tag, 10);
      if (tagNum >= 26 && tagNum <= 51 && t.children) {
        var findChild = function (childTag) {
          for (var j = 0; j < t.children.length; j += 1) if (t.children[j].tag === childTag) return t.children[j];
          return undefined;
        };
        merchantAccountInfo.push({
          tag: t.tag,
          globallyUniqueId: findChild('00') ? findChild('00').value : '',
          merchantId: (findChild('01') ? findChild('01').value : '') || (findChild('02') ? findChild('02').value : ''),
          merchantCriteria: findChild('03') ? findChild('03').value : undefined,
          fields: t.children
        });
      }
    }
    return {
      version: findTag('00') ? findTag('00').value : '01',
      method: methodValue === '12' ? 'dynamic' : 'static',
      merchantAccountInfo: merchantAccountInfo,
      merchantCategoryCode: findTag('52') ? findTag('52').value : '',
      currency: findTag('53') ? findTag('53').value : '360',
      amount: findTag('54') ? findTag('54').value : undefined,
      tipIndicator: tipIndicatorValue === '01' ? 'prompt' : tipIndicatorValue === '02' ? 'fixed' : tipIndicatorValue === '03' ? 'percentage' : undefined,
      tipFixed: findTag('56') ? findTag('56').value : undefined,
      tipPercentage: findTag('57') ? findTag('57').value : undefined,
      countryCode: findTag('58') ? findTag('58').value : 'ID',
      merchantName: findTag('59') ? findTag('59').value : '',
      merchantCity: findTag('60') ? findTag('60').value : '',
      postalCode: findTag('61') ? findTag('61').value : '',
      additionalData: findTag('62') ? findTag('62').children : undefined,
      crc: findTag('63') ? findTag('63').value : '',
      raw: raw
    };
  }

  function calculateCRC16(str) {
    var crc = 0xffff;
    for (var i = 0; i < str.length; i += 1) {
      crc ^= str.charCodeAt(i) << 8;
      for (var j = 0; j < 8; j += 1) {
        if (crc & 0x8000) crc = ((crc << 1) ^ 0x1021) & 0xffff;
        else crc = (crc << 1) & 0xffff;
      }
    }
    return (crc & 0xffff).toString(16).toUpperCase().padStart(4, '0');
  }

  function validateQRIS(qrisString) {
    var errors = [];
    var str = String(qrisString || '').trim();
    if (!str) return { valid: false, errors: ['String QRIS kosong'] };
    if (str.indexOf('000201') !== 0) errors.push('QRIS harus diawali Payload Format Indicator "000201"');
    if (str.length < 20) {
      errors.push('String QRIS terlalu pendek');
      return { valid: false, errors: errors };
    }
    var dataWithoutCRC = str.substring(0, str.length - 4);
    var declaredCRC = str.substring(str.length - 4);
    var calculatedCRC = calculateCRC16(dataWithoutCRC);
    if (declaredCRC.toUpperCase() !== calculatedCRC) {
      errors.push('CRC tidak cocok: diharapkan ' + calculatedCRC + ', ditemukan ' + declaredCRC.toUpperCase());
    }
    var elements = parseTLV(str);
    if (!elements.length) {
      errors.push('Gagal membaca struktur TLV');
      return { valid: false, errors: errors };
    }
    var tags = {};
    elements.forEach(function (el) { tags[el.tag] = true; });
    [
      ['00', 'Payload Format Indicator'],
      ['01', 'Point of Initiation Method'],
      ['52', 'Merchant Category Code'],
      ['53', 'Transaction Currency'],
      ['58', 'Country Code'],
      ['59', 'Merchant Name'],
      ['60', 'Merchant City'],
      ['63', 'CRC']
    ].forEach(function (req) {
      if (!tags[req[0]]) errors.push('Tag wajib ' + req[0] + ' (' + req[1] + ') tidak ada');
    });
    var method = null;
    elements.forEach(function (el) { if (el.tag === '01') method = el; });
    if (method && method.value !== '11' && method.value !== '12') {
      errors.push('Point of Initiation Method tidak valid: "' + method.value + '" (harus "11" atau "12")');
    }
    var hasMerchant = elements.some(function (el) {
      var n = parseInt(el.tag, 10);
      return n >= 26 && n <= 51;
    });
    if (!hasMerchant) errors.push('Tidak ada Merchant Account Information (tag 26–51)');
    return { valid: errors.length === 0, errors: errors };
  }

  function buildTLVString(elements) {
    return elements.map(function (el) {
      var value = el.children ? buildTLVString(el.children) : el.value;
      var length = String(value.length).padStart(2, '0');
      return el.tag + length + value;
    }).join('');
  }

  function makeTLV(tag, value, name) {
    return { tag: tag, name: name || '', length: value.length, value: value };
  }

  function convertQRIS(qrisString, options) {
    var amountNumber = Math.floor(Number(options && options.amount));
    if (!Number.isFinite(amountNumber) || amountNumber <= 0) {
      throw new Error('Nominal QRIS tidak valid.');
    }
    if (amountNumber > 99999999) {
      throw new Error('Nominal melebihi batas QRIS (maks Rp 99.999.999).');
    }
    var elements = parseTLV(String(qrisString || '').trim());
    var result = [];
    var amountInserted = false;
    // Urutan tag setelah nominal yang dikehendaki EMVCo (58–62) atau 63.
    var insertBefore = { '58': true, '59': true, '60': true, '61': true, '62': true, '63': true };
    var managedTags = { '54': true, '55': true, '56': true, '57': true, '63': true };
    var pushAmount = function () {
      result.push(makeTLV('54', String(amountNumber), 'Transaction Amount'));
    };

    for (var i = 0; i < elements.length; i += 1) {
      var el = elements[i];
      if (managedTags[el.tag]) continue;
      if (el.tag === '01') {
        // statis ("11") → dinamis ("12")
        result.push(makeTLV('01', '12', 'Point of Initiation Method'));
        continue;
      }
      if (!amountInserted && insertBefore[el.tag]) {
        pushAmount();
        amountInserted = true;
      }
      result.push(el);
    }
    if (!amountInserted) pushAmount();

    var withoutCRC = buildTLVString(result);
    var crcInput = withoutCRC + '6304';
    return crcInput + calculateCRC16(crcInput);
  }

  global.QRIS = {
    parseTLV: parseTLV,
    parseQRIS: parseQRIS,
    validateQRIS: validateQRIS,
    convertQRIS: convertQRIS,
    calculateCRC16: calculateCRC16
  };
})(typeof window !== 'undefined' ? window : globalThis);