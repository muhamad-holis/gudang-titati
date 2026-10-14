import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../utils.dart';

const _units = ['kg', 'gram', 'liter', 'pcs', 'pak', 'ikat', 'butir', 'porsi', 'bungkus'];

/// Pilihan jalur bahan mentah: diolah di produksi, langsung ke cabang, atau keduanya.
Widget _jalurPicker(String jalur, void Function(String) onChanged) {
  const opsi = [
    ['olah', 'Diolah di produksi'],
    ['cabang', 'Langsung ke cabang'],
    ['dua', 'Keduanya'],
  ];
  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Padding(
      padding: EdgeInsets.only(top: 10, bottom: 4),
      child: Text('Jalur barang', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
    ),
    Wrap(spacing: 6, children: [
      for (final o in opsi) ChoiceChip(label: Text(o[1], style: const TextStyle(fontSize: 12)), selected: jalur == o[0], onSelected: (_) => onChanged(o[0])),
    ]),
    const Padding(
      padding: EdgeInsets.only(top: 4),
      child: Text('Langsung ke cabang = tidak lewat produksi dan tidak dijual satuan (mis. kemasan, saus meja, sayuran).', style: TextStyle(fontSize: 11, color: Colors.grey)),
    ),
  ]);
}

Widget _chipRow(List<String> values, TextEditingController c, void Function(VoidCallback) setS) {
  return Wrap(spacing: 6, runSpacing: 0, children: [
    for (final v in values) ActionChip(label: Text(v, style: const TextStyle(fontSize: 12)), onPressed: () => setS(() => c.text = v)),
  ]);
}

List<String> categoryChoices(AppState s, String kind) {
  final fromItems = s.items.where((i) => i.kind == kind).map((i) => i.category);
  final base = kind == 'jadi' ? ['Bahan jadi'] : <String>[];
  return {...base, ...s.categories, ...fromItems}.toList();
}

/// Pilih bahan (kind null = semua jenis).
/// sellable = hanya barang yang boleh diminta cabang (bahan jadi, siap jual, atau bahan/perlengkapan cabang).
/// noSiap = hanya bahan mentah untuk produksi (sembunyikan barang siap jual dan barang khusus cabang).
Future<Item?> pickItem(BuildContext context, {String? kind, String? stockLocation, bool sellable = false, bool noSiap = false}) {
  return showModalBottomSheet<Item>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _PickSheet(kind: kind, stockLocation: stockLocation, sellable: sellable, noSiap: noSiap),
  );
}

class _PickSheet extends StatefulWidget {
  final String? kind;
  final String? stockLocation;
  final bool sellable, noSiap;
  const _PickSheet({required this.kind, required this.stockLocation, this.sellable = false, this.noSiap = false});
  @override
  State<_PickSheet> createState() => _PickSheetState();
}

class _PickSheetState extends State<_PickSheet> {
  String q = '';
  String cat = 'Semua';

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final all = s.items
        .where((i) =>
            i.active &&
            (widget.kind == null || i.kind == widget.kind) &&
            (!widget.sellable || i.kind == 'jadi' || i.siapJual || i.keCabang) &&
            (!widget.noSiap || (!i.siapJual && i.untukProduksi)))
        .toList();
    final cats = ['Semua', ...({...all.map((i) => i.category)}.toList()..sort())];
    final list = all.where((i) => (cat == 'Semua' || i.category == cat) && i.name.toLowerCase().contains(q.toLowerCase())).toList();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(children: [
          const SizedBox(height: 8),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              onChanged: (v) => setState(() => q = v),
              decoration: InputDecoration(
                hintText: 'Cari bahan...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
              for (final c in cats)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(label: Text(c), selected: cat == c, onSelected: (_) => setState(() => cat = c)),
                ),
            ]),
          ),
          Expanded(
            child: list.isEmpty
                ? const Center(child: Text('Bahan tidak ditemukan', style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (c, i) {
                      final it = list[i];
                      final stk = widget.stockLocation == null ? null : s.stockAt(widget.stockLocation!, it.id);
                      return ListTile(
                        title: Text(it.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text('${it.category} • ${it.unit}${it.siapJual ? ' • siap jual' : ''}${stk == null ? '' : ' • stok ${_f(stk)}'}'),
                        onTap: () => Navigator.pop(context, it),
                      );
                    },
                  ),
          ),
          if (s.role != 'cabang')
            Padding(
              padding: const EdgeInsets.all(12),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                onPressed: () async {
                  final it = await addItemDialog(context, s, kind: widget.kind);
                  if (it != null && context.mounted) Navigator.pop(context, it);
                },
                icon: const Icon(Icons.add),
                label: const Text('Tambah bahan baru'),
              ),
            ),
        ]),
      ),
    );
  }

  String _f(double q) => q == q.roundToDouble() ? q.toStringAsFixed(0) : q.toStringAsFixed(2);
}

/// Tambah bahan baru. kind null = pengguna memilih jenisnya.
Future<Item?> addItemDialog(BuildContext context, AppState s, {String? kind}) {
  final name = TextEditingController();
  final unit = TextEditingController(text: 'kg');
  var k = kind ?? 'mentah';
  var siap = false;
  // barang yang ditambah gudang langsung bisa dikirim ke produksi maupun ke cabang
  var jalur = s.role == 'gudang' ? 'dua' : 'olah';
  final cat = TextEditingController(text: k == 'jadi' ? 'Bahan jadi' : '');
  String? err;
  var saving = false;
  return showDialog<Item>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, setS) => AlertDialog(
        title: Text(kind == null ? 'Tambah bahan' : (kind == 'jadi' ? 'Tambah bahan jadi' : 'Tambah bahan mentah')),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (kind == null)
              Row(children: [
                ChoiceChip(label: const Text('Bahan mentah'), selected: k == 'mentah', onSelected: (_) => setS(() => k = 'mentah')),
                const SizedBox(width: 8),
                ChoiceChip(label: const Text('Bahan jadi'), selected: k == 'jadi', onSelected: (_) => setS(() => k = 'jadi')),
              ]),
            TextField(controller: name, autofocus: true, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Nama bahan')),
            const SizedBox(height: 8),
            TextField(controller: cat, decoration: const InputDecoration(labelText: 'Kategori')),
            _chipRow(categoryChoices(s, k), cat, setS),
            const SizedBox(height: 8),
            TextField(controller: unit, decoration: const InputDecoration(labelText: 'Satuan')),
            _chipRow(_units, unit, setS),
            if (k == 'mentah')
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Barang siap jual', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                subtitle: const Text('Dikirim gudang langsung ke cabang tanpa produksi (mis. air mineral)', style: TextStyle(fontSize: 12)),
                value: siap,
                onChanged: (v) => setS(() => siap = v ?? false),
              ),
            if (k == 'mentah' && !siap) _jalurPicker(jalur, (v) => setS(() => jalur = v)),
            if (err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err!, style: const TextStyle(color: red))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Batal')),
          FilledButton(
            onPressed: saving
                ? null
                : () async {
                    if (name.text.trim().isEmpty || cat.text.trim().isEmpty || unit.text.trim().isEmpty) {
                      setS(() => err = 'Nama, kategori, dan satuan wajib diisi');
                      return;
                    }
                    setS(() {
                      saving = true;
                      err = null;
                    });
                    try {
                      final it = await s.addItem(name.text, k, cat.text, unit.text, siapJual: k == 'mentah' && siap, jalur: jalur);
                      if (d.mounted) Navigator.pop(d, it);
                    } catch (e) {
                      if (d.mounted) {
                        setS(() {
                          saving = false;
                          err = errText(e);
                        });
                      }
                    }
                  },
            child: const Text('Simpan'),
          ),
        ],
      ),
    ),
  );
}

Future<bool> _konfirmasi(BuildContext ctx, String judul, String isi, String tombol) async {
  final r = await showDialog<bool>(
    context: ctx,
    builder: (c) => AlertDialog(
      title: Text(judul),
      content: Text(isi),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Batal')),
        FilledButton(style: FilledButton.styleFrom(backgroundColor: red), onPressed: () => Navigator.pop(c, true), child: Text(tombol)),
      ],
    ),
  );
  return r == true;
}

Future<Item?> _pilihTujuan(BuildContext ctx, AppState s, Item it) {
  final opsi = s.items.where((x) => x.kind == it.kind && x.id != it.id).toList();
  Item? pilih;
  return showDialog<Item>(
    context: ctx,
    builder: (c) => StatefulBuilder(
      builder: (c, setS) => AlertDialog(
        title: Text('Gabungkan "${it.name}" ke...'),
        content: opsi.isEmpty
            ? const Text('Tidak ada barang lain dengan jenis yang sama.')
            : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Stok dan seluruh riwayat dipindah ke barang tujuan, lalu barang ini dihapus. Satuan keduanya harus sama.', style: TextStyle(fontSize: 12)),
                const SizedBox(height: 8),
                DropdownButtonFormField<Item>(
                  isExpanded: true,
                  value: pilih,
                  hint: const Text('Pilih barang tujuan'),
                  items: [for (final x in opsi) DropdownMenuItem(value: x, child: Text('${x.name} (${x.unit})', overflow: TextOverflow.ellipsis))],
                  onChanged: (v) => setS(() => pilih = v),
                ),
              ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Batal')),
          FilledButton(onPressed: pilih == null ? null : () => Navigator.pop(c, pilih), child: const Text('Lanjut')),
        ],
      ),
    ),
  );
}

/// Ubah bahan (owner). Mengembalikan true jika tersimpan.
Future<bool?> editItemDialog(BuildContext context, AppState s, Item it) {
  final name = TextEditingController(text: it.name);
  final cat = TextEditingController(text: it.category);
  final unit = TextEditingController(text: it.unit);
  var active = it.active;
  var siap = it.siapJual;
  var jalur = it.jalur;
  final rend = TextEditingController(text: it.rendemenStd == null ? '' : fmtQty(it.rendemenStd!));
  final minStok = TextEditingController(text: it.stokMin > 0 ? fmtQty(it.stokMin) : '');
  final unitEcer = TextEditingController(text: it.unitEcer);
  final isiEcer = TextEditingController(text: it.punyaEcer ? fmtQty(it.isiEcer) : '');
  final hargaStd = TextEditingController(text: it.sellPriceDefault > 0 ? it.sellPriceDefault.round().toString() : '');
  String? err;
  var saving = false;
  return showDialog<bool>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, setS) => AlertDialog(
        title: Text('Ubah ${it.kind == 'jadi' ? 'bahan jadi' : 'bahan mentah'}'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Nama bahan')),
            const SizedBox(height: 8),
            TextField(controller: cat, decoration: const InputDecoration(labelText: 'Kategori')),
            _chipRow(categoryChoices(s, it.kind), cat, setS),
            const SizedBox(height: 8),
            TextField(controller: unit, decoration: const InputDecoration(labelText: 'Satuan')),
            _chipRow(_units, unit, setS),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Aktif (muncul di pilihan)'), value: active, onChanged: (v) => setS(() => active = v)),
            TextField(
              controller: minStok,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Stok minimum gudang (opsional)',
                suffixText: it.unit,
                helperText: 'Beranda memberi peringatan bila stok gudang sama dengan atau di bawah angka ini. Kosong = tidak dipantau.',
                helperMaxLines: 3,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: TextField(
                controller: hargaStd,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Harga jual standar ke cabang (opsional)',
                  prefixText: 'Rp ',
                  suffixText: '/ ${it.unit}',
                  helperText: 'Jadi isian awal saat kirim ke cabang, masih bisa diubah tiap kiriman. Kosong = isi manual.',
                  helperMaxLines: 3,
                ),
              ),
            ),
            if (it.kind == 'jadi' || siap) ...[
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: TextField(
                  controller: unitEcer,
                  onChanged: (_) => setS(() {}),
                  decoration: InputDecoration(
                    labelText: 'Satuan eceran di cabang (opsional)',
                    helperText: 'Mis. botol, bila gudang mencatat dalam ${unit.text.trim().isEmpty ? it.unit : unit.text.trim()} tetapi cabang menjual ecer. Kosong = tanpa konversi.',
                    helperMaxLines: 3,
                  ),
                ),
              ),
              if (unitEcer.text.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: TextField(
                    controller: isiEcer,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Isi per ${unit.text.trim().isEmpty ? it.unit : unit.text.trim()}',
                      suffixText: unitEcer.text.trim(),
                      helperText: 'Mis. 24 botol per dus. Stok cabang otomatis dihitung dalam ${unitEcer.text.trim()} saat cabang menekan Terima.',
                      helperMaxLines: 3,
                    ),
                  ),
                ),
            ],
            if (it.kind == 'jadi')
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: TextField(
                  controller: rend,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Rendemen standar (opsional)',
                    helperText: 'Hasil jadi dari 1 satuan bahan mentah. Mis. 10 kg bahan jadi 12 kg: isi 1,2. Kosong = setoran selalu minta ACC owner.',
                    helperMaxLines: 4,
                  ),
                ),
              ),
            if (it.kind == 'mentah')
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Barang siap jual'),
                subtitle: const Text('Gudang kirim langsung ke cabang, tanpa produksi', style: TextStyle(fontSize: 12)),
                value: siap,
                onChanged: (v) => setS(() => siap = v),
              ),
            if (it.kind == 'mentah' && !siap) _jalurPicker(jalur, (v) => setS(() => jalur = v)),
            if (err != null) Text(err!, style: const TextStyle(color: red)),
            if (s.isOwner || s.role == 'gudang') ...[
              const Divider(height: 24),
              Wrap(spacing: 8, children: [
                TextButton.icon(
                  onPressed: saving
                      ? null
                      : () async {
                          final ok = await _konfirmasi(d, 'Hapus "${it.name}"?',
                              'Barang yang belum pernah dipakai transaksi dihapus permanen. Barang yang sudah punya riwayat tidak dihapus, hanya disembunyikan (nonaktif) supaya laporan lama tetap benar. Stoknya harus kosong dulu.', 'Hapus');
                          if (!ok) return;
                          setS(() {
                            saving = true;
                            err = null;
                          });
                          try {
                            final hasil = await s.hapusBarang(it.id);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  content: Text(hasil == 'hapus' ? '"${it.name}" dihapus permanen' : '"${it.name}" punya riwayat transaksi, jadi disembunyikan (nonaktif)')));
                            }
                            if (d.mounted) Navigator.pop(d, true);
                          } catch (e) {
                            if (d.mounted) {
                              setS(() {
                                saving = false;
                                err = errText(e);
                              });
                            }
                          }
                        },
                  icon: const Icon(Icons.delete_outline, color: red, size: 18),
                  label: const Text('Hapus', style: TextStyle(color: red)),
                ),
                if (s.isOwner)
                  TextButton.icon(
                  onPressed: saving
                      ? null
                      : () async {
                          final tujuan = await _pilihTujuan(d, s, it);
                          if (tujuan == null || !d.mounted) return;
                          final ok = await _konfirmasi(d, 'Gabungkan barang?',
                              'Stok dan riwayat "${it.name}" dipindah ke "${tujuan.name}", lalu "${it.name}" dihapus. Tidak bisa dibatalkan.', 'Gabungkan');
                          if (!ok) return;
                          setS(() {
                            saving = true;
                            err = null;
                          });
                          try {
                            await s.gabungBarang(it.id, tujuan.id);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('"${it.name}" digabung ke "${tujuan.name}"')));
                            }
                            if (d.mounted) Navigator.pop(d, true);
                          } catch (e) {
                            if (d.mounted) {
                              setS(() {
                                saving = false;
                                err = errText(e);
                              });
                            }
                          }
                        },
                  icon: const Icon(Icons.merge_type, size: 18),
                  label: const Text('Gabungkan'),
                ),
              ]),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Batal')),
          FilledButton(
            onPressed: saving
                ? null
                : () async {
                    if (name.text.trim().isEmpty || cat.text.trim().isEmpty || unit.text.trim().isEmpty) {
                      setS(() => err = 'Nama, kategori, dan satuan wajib diisi');
                      return;
                    }
                    double? newRend;
                    if (it.kind == 'jadi' && rend.text.trim().isNotEmpty) {
                      newRend = parseQty(rend.text);
                      if (newRend == null || newRend <= 0) {
                        setS(() => err = 'Rendemen harus berupa angka lebih dari 0');
                        return;
                      }
                    }
                    final rendChanged = it.kind == 'jadi' && newRend != it.rendemenStd;
                    var newMin = 0.0;
                    if (minStok.text.trim().isNotEmpty) {
                      final m = parseQty(minStok.text);
                      if (m == null || m < 0) {
                        setS(() => err = 'Stok minimum harus berupa angka 0 atau lebih');
                        return;
                      }
                      newMin = m;
                    }
                    var newHarga = 0.0;
                    if (hargaStd.text.trim().isNotEmpty) {
                      final h = parseQty(hargaStd.text);
                      if (h == null || h < 0) {
                        setS(() => err = 'Harga jual standar harus berupa angka 0 atau lebih');
                        return;
                      }
                      newHarga = h;
                    }
                    final ecerUnit = (it.kind == 'jadi' || siap) ? unitEcer.text.trim() : it.unitEcer;
                    var ecerIsi = 1.0;
                    if (ecerUnit.isNotEmpty) {
                      final v = parseQty(isiEcer.text);
                      if (v == null || v <= 1 || v != v.truncateToDouble()) {
                        setS(() => err = 'Isi per ${unit.text.trim()} harus bilangan bulat lebih dari 1');
                        return;
                      }
                      ecerIsi = v;
                    }
                    final ecerBerubah = ecerUnit != it.unitEcer || (ecerUnit.isNotEmpty && ecerIsi != it.isiEcer);
                    setS(() => saving = true);
                    try {
                      if (ecerBerubah) await s.aturSatuanEcer(it.id, ecerUnit, ecerIsi);
                      await s.updateItem(it.id,
                          name: name.text,
                          category: cat.text,
                          unit: unit.text,
                          active: active,
                          siapJual: (it.kind == 'mentah' && siap != it.siapJual) ? siap : null,
                          rendemenStd: newRend,
                          setRendemen: rendChanged,
                          stokMin: newMin,
                          setStokMin: newMin != it.stokMin,
                          sellPriceDefault: newHarga != it.sellPriceDefault ? newHarga : null,
                          jalur: (it.kind == 'mentah' && jalur != it.jalur) ? jalur : null);
                      if (d.mounted) Navigator.pop(d, true);
                    } catch (e) {
                      if (d.mounted) {
                        setS(() {
                          saving = false;
                          err = errText(e);
                        });
                      }
                    }
                  },
            child: const Text('Simpan'),
          ),
        ],
      ),
    ),
  );
}
