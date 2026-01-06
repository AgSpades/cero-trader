# Cero Trader

A multi-platform trade relayer system designed for MetaTrader 5 and TradingView. Cero Trader enables users to seamlessly relay trades from TradingView alerts to MetaTrader 5, allowing for automated trading strategies and improved trade execution.

> Note: Sending alerts from TradingView to MetaTrader 5 requires the use of a webhook service. Configuration details can be found in the documentation.

## Pre-requisites
- MetaTrader 5 installed on your computer.
- A TradingView account with access to alert functionality. Open here for a $15 credit: [TradingView Signup](https://in.tradingview.com/?aff_id=161801&source=github).
- [Cloudflared](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/downloads/) installed for webhook tunneling.