# Cero Trader

A multi-platform trade relayer system designed for MetaTrader 5 and TradingView. Cero Trader enables users to seamlessly relay trades from TradingView alerts to MetaTrader 5, allowing for automated trading strategies and improved trade execution.

> Note: Sending alerts from TradingView to MetaTrader 5 requires the use of a webhook service. Configuration details can be found in the documentation.

## Pre-requisites

- MetaTrader 5 installed on your computer.
- Python 3.11 or higher installed.
- Required Python packages installed. You can install them using:
  ```bash
  cd relay-server
  pip install -r requirements.txt
  ```
- A TradingView account with access to alert functionality. Open here for a $15 credit: [TradingView Signup](https://in.tradingview.com/?aff_id=161801&source=github).
- [Cloudflared](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/downloads/) installed for webhook tunneling.
- A basic understanding of how to create alerts in TradingView.

## Setup Instructions

1. **Clone the Repository**:
   ```bash
   git clone https://github.com/AgSpades/cero-trader.git
   ```
2. **Compile the MetaTrader 5 Expert Advisor**:
   - Open MetaTrader 5.
   - Navigate to `File` > `Open Data Folder` > `MQL5` > `Experts`.
   - Copy the `CTV.mq5` file from the `mt5-client/Experts` directory into this folder.
   - Copy the files from the `mt5-client/Libraries` and `mt5-client/Include` directories into the `MQL5/Libraries` and `MQL5/Include` folders.
   - Open the MetaEditor, find `CTV.mq5`, and compile it.
3. **Set Up the Relay Server**:
   - Navigate to the `relay-server` directory.
   - Run the server using:
     ```bash
     python run_server.py
     ```
4. **Set Up Cloudflared**:
   - Start Cloudflared to create a tunnel to your local server:
     ```bash
     cloudflared tunnel --url http://localhost:8080
     ```
   - Note the generated public URL for use in TradingView alerts.
5. **Configure TradingView Alerts**:
   - Create a new alert in TradingView.
   - Set the alert action to "Webhook URL" and enter the Cloudflared URL with the `/webhook` endpoint.
   - In the alert message, paste the following JSON template for BUY and SELL signals:
     ```json
     {
       "signal": "BUY",
       "symbol": "{{ticker}}",
       "price": "{{close}}",
       "time": "{{timenow}}",
       "interval": "{{interval}}",
       "volume": "{{volume}}"
     }
     ```
     Replace `"BUY"` with `"SELL"` for sell signals.

## Testing the Setup

Make a CURL request to your Cloudflared URL to ensure the relay server is receiving requests:

```bash
curl -X POST <your-cloudflared-url>/webhook -H "Content-Type: application/json" -d '{"signal":"BUY","symbol":"EURUSD","price":1.2345,"time":"2024-01-01 12:00:00","interval":"1H","volume":1000}'
```
Replace `<your-cloudflared-url>` with your actual Cloudflared URL.
If everything is set up correctly, you should see the trade being executed in MetaTrader 5.

