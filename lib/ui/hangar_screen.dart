import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';

import '../core/achievements.dart';
import '../core/garage.dart';
import '../game/player.dart';
import 'module_icon.dart';

/// Hangar: onde o jogador gasta créditos em skins e módulos e monta o loadout.
/// É a camada de meta-progressão pedida (acessórios, naves auxiliares, skins).
class HangarScreen extends StatelessWidget {
  const HangarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF05030F),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: garage,
          builder: (context, _) => Column(
            children: [
              // Cabeçalho: voltar + créditos.
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 18, 4),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back_rounded,
                          color: Colors.white70),
                    ),
                    const Text(
                      'HANGAR',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 3,
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    _CreditsChip(credits: garage.credits),
                  ],
                ),
              ),
              const _ShipPreview(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
                  children: [
                    _sectionLabel(
                        'MÓDULOS  ·  ${garage.equipped.length}/${garage.slots} equipados'),
                    for (final m in ShipModule.values) _ModuleRow(module: m),
                    if (!garage.hasThirdSlot) const _ThirdSlotRow(),
                    const SizedBox(height: 18),
                    _sectionLabel('SKINS'),
                    for (final s in ShipSkin.values) _SkinRow(skin: s),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10, top: 4),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
            color: Colors.white38,
          ),
        ),
      );
}

class _CreditsChip extends StatelessWidget {
  const _CreditsChip({required this.credits});
  final int credits;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0xFFFFD23F).withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.paid_rounded, color: Color(0xFFFFD23F), size: 20),
          const SizedBox(width: 6),
          Text(
            '$credits',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

/// Prévia da nave com a skin equipada, desenhada pelo mesmo pintor do jogo.
class _ShipPreview extends StatelessWidget {
  const _ShipPreview();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 150,
      margin: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        gradient: const RadialGradient(
          colors: [Color(0xFF1A1140), Color(0xFF05030F)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: CustomPaint(
        painter: _ShipPreviewPainter(garage.skin, garage.equipped),
        child: const Center(),
      ),
    );
  }
}

class _ShipPreviewPainter extends CustomPainter {
  _ShipPreviewPainter(this.skin, this.modules);
  final ShipSkin skin;
  final Set<ShipModule> modules;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(size.width / 2, size.height / 2 + 10);
    canvas.scale(1.6);
    // Reaproveita o desenho da nave do jogo mantendo a fidelidade visual.
    paintShipPreview(canvas, skin, modules);
  }

  @override
  bool shouldRepaint(_ShipPreviewPainter old) =>
      old.skin != skin || !setEquals(old.modules, modules);
}

class _ModuleRow extends StatelessWidget {
  const _ModuleRow({required this.module});
  final ShipModule module;

  @override
  Widget build(BuildContext context) {
    final owned = garage.ownsModule(module);
    final equipped = garage.isEquipped(module);
    final canAfford = garage.credits >= module.cost;
    final level = garage.moduleLevel(module);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: equipped
            ? const Color(0xFF35E1F5).withValues(alpha: 0.10)
            : Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: equipped
              ? const Color(0xFF35E1F5).withValues(alpha: 0.6)
              : Colors.white12,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              ModuleIcon(module, owned: owned, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          module.label,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: owned ? Colors.white : Colors.white54,
                          ),
                        ),
                        if (owned) ...[
                          const SizedBox(width: 8),
                          // Pips de nível: I / II / III.
                          for (var i = 1; i <= kMaxModuleLevel; i++)
                            Container(
                              width: 9,
                              height: 9,
                              margin: const EdgeInsets.only(right: 3),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: i <= level
                                    ? const Color(0xFFFFD23F)
                                    : Colors.white12,
                              ),
                            ),
                        ],
                      ],
                    ),
                    Text(
                      owned ? module.tierDesc(level) : module.description,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white38,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _actionButton(context, owned, equipped, canAfford),
            ],
          ),
          // Melhoria de nível: aparece quando o módulo é seu e não está no teto.
          if (owned && level < kMaxModuleLevel)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  const SizedBox(width: 38),
                  Expanded(
                    child: Text(
                      'Nv.${level + 1}: ${module.tierDesc(level + 1)}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF4BF07A),
                      ),
                    ),
                  ),
                  _PriceButton(
                    cost: module.upgradeCost(level),
                    enabled: garage.credits >= module.upgradeCost(level),
                    label: 'MELHORAR',
                    onTap: () => garage.upgradeModule(module),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _actionButton(
      BuildContext context, bool owned, bool equipped, bool canAfford) {
    if (!owned) {
      return _PriceButton(
        cost: module.cost,
        enabled: canAfford,
        onTap: () => garage.buyModule(module),
      );
    }
    return GestureDetector(
      onTap: () async {
        final ok = await garage.toggleModule(module);
        if (!ok && !equipped && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Slots cheios — desequipe um módulo primeiro'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: equipped ? const Color(0xFF35E1F5) : Colors.white10,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          equipped ? 'EQUIPADO' : 'EQUIPAR',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            color: equipped ? const Color(0xFF05030F) : Colors.white,
          ),
        ),
      ),
    );
  }
}

/// O 3º slot: a compra cara que muda o teto do loadout.
class _ThirdSlotRow extends StatelessWidget {
  const _ThirdSlotRow();

  @override
  Widget build(BuildContext context) {
    final canAfford = garage.credits >= kThirdSlotCost;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF9B4DFF).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: const Color(0xFF9B4DFF).withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          const Icon(Icons.add_circle_outline_rounded,
              color: Color(0xFF9B4DFF), size: 26),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '3º SLOT DE MÓDULO',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'Equipe três módulos ao mesmo tempo',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white38,
                  ),
                ),
              ],
            ),
          ),
          _PriceButton(
            cost: kThirdSlotCost,
            enabled: canAfford,
            onTap: () => garage.buyThirdSlot(),
          ),
        ],
      ),
    );
  }
}

class _SkinRow extends StatelessWidget {
  const _SkinRow({required this.skin});
  final ShipSkin skin;

  @override
  Widget build(BuildContext context) {
    final owned = garage.ownsSkin(skin);
    final equipped = garage.skin == skin;
    // ESPECTRO é troféu: só se resgata com a condecoração "Intocável".
    final trophyLocked =
        skin.isTrophy && !achievements.isUnlocked(Achievement.noMissBoss);
    final canAfford = !trophyLocked && garage.credits >= skin.cost;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: equipped
            ? skin.accent.withValues(alpha: 0.12)
            : Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: equipped ? skin.accent.withValues(alpha: 0.7) : Colors.white12,
        ),
      ),
      child: Row(
        children: [
          // Amostra de cores da skin.
          Row(
            children: [
              _swatch(skin.hull),
              _swatch(skin.accent),
              _swatch(skin.wing),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  skin.label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: owned ? Colors.white : Colors.white54,
                  ),
                ),
                if (skin.isTrophy && !owned)
                  const Text(
                    'Prêmio: chefe sem levar dano',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFFFD23F),
                    ),
                  ),
              ],
            ),
          ),
          if (!owned && trophyLocked)
            const Icon(Icons.lock_rounded, color: Colors.white24, size: 22)
          else if (!owned && skin.isTrophy)
            _PriceButton(
              cost: 0,
              enabled: true,
              label: 'RESGATAR',
              onTap: () => garage.buySkin(skin),
            )
          else if (!owned)
            _PriceButton(
              cost: skin.cost,
              enabled: canAfford,
              onTap: () => garage.buySkin(skin),
            )
          else
            GestureDetector(
              onTap: () => garage.equipSkin(skin),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: equipped ? skin.accent : Colors.white10,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  equipped ? 'USANDO' : 'USAR',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: equipped ? const Color(0xFF05030F) : Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _swatch(Color c) => Container(
        width: 14,
        height: 22,
        margin: const EdgeInsets.only(right: 3),
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(3),
        ),
      );
}

class _PriceButton extends StatelessWidget {
  const _PriceButton({
    required this.cost,
    required this.enabled,
    required this.onTap,
    this.label,
  });

  final int cost;
  final bool enabled;
  final VoidCallback onTap;

  /// Texto extra antes do preço (ex.: "MELHORAR"). Preço 0 mostra só o texto.
  final String? label;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: enabled
              ? const Color(0xFFFFD23F)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (label != null) ...[
              Text(
                label!,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: enabled ? const Color(0xFF05030F) : Colors.white38,
                ),
              ),
              if (cost > 0) const SizedBox(width: 6),
            ],
            if (cost > 0 || label == null) ...[
              Icon(Icons.paid_rounded,
                  size: 14,
                  color: enabled ? const Color(0xFF05030F) : Colors.white38),
              const SizedBox(width: 4),
              Text(
                '$cost',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: enabled ? const Color(0xFF05030F) : Colors.white38,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
