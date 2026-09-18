class NominalOption {
  const NominalOption({
    required this.amount,
    required this.kwh,
    required this.electricityCost,
    required this.pbjtTl,
    this.ppn = 0,
    this.serviceFee = 0,
  });

  final int amount;
  final double kwh;
  final int electricityCost;
  final int pbjtTl;
  final int ppn;
  final int serviceFee;

  int get total => electricityCost + pbjtTl + ppn + serviceFee;
}
